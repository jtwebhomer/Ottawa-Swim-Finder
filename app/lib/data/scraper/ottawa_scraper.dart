import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/sync_thresholds.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/ottawa_time.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/facility_fetch_tier.dart';
import '../../domain/entities/facility_type.dart';
import '../../domain/entities/facility_sync_diagnostic.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/entities/scrape_log.dart';
import '../../domain/entities/sync_log.dart';
import '../../domain/entities/sync_progress.dart';
import '../../domain/entities/sync_status.dart';
import '../../domain/repositories/repositories.dart';
import '../services/blocked_page_detector.dart';
import '../services/facility_discovery_service.dart';
import '../services/facility_sync_logger.dart';
import '../services/fetch/tiered_facility_page_fetcher.dart';
import '../services/ottawa_http_client.dart';
import '../services/schedule_sanity_checker.dart';
import '../services/schedule_trace_logger.dart';
import '../services/sync_safety_guard.dart';
import 'parsers/schedule_parser.dart';

class _CommitCandidate {
  _CommitCandidate({
    required this.facility,
    required this.entries,
    required this.hash,
    required this.snapshotPath,
    required this.existingCount,
    required this.durationMs,
    required this.validationClass,
    required this.sanityNote,
  });

  final Facility facility;
  final List<ScheduleEntry> entries;
  final String hash;
  final String? snapshotPath;
  final int existingCount;
  final int durationMs;
  final FacilityValidationClass validationClass;
  final String sanityNote;
}

class _FacilityPhaseResult {
  _FacilityPhaseResult({
    required this.facility,
    required this.fetchOutcome,
    required this.validationClass,
    required this.existingCount,
    required this.diagnostic,
    this.entries,
    this.hash,
    this.snapshotPath,
    this.rejectReason,
    this.durationMs = 0,
    this.commitCandidate,
    this.countsAsSuccess = false,
  });

  final Facility facility;
  final FacilityFetchOutcome fetchOutcome;
  final FacilityValidationClass validationClass;
  final int existingCount;
  final FacilitySyncDiagnostic diagnostic;
  final List<ScheduleEntry>? entries;
  final String? hash;
  final String? snapshotPath;
  final String? rejectReason;
  final int durationMs;
  final _CommitCandidate? commitCandidate;
  final bool countsAsSuccess;
}

class OttawaScraper {
  OttawaScraper({
    required FacilityRepository facilityRepo,
    required ScheduleRepository scheduleRepo,
    required ScrapeLogRepository scrapeLogRepo,
    SyncLogRepository? syncLogRepo,
    OttawaHttpClient? httpClient,
    TieredFacilityPageFetcher? tieredFetcher,
    ScheduleTraceLogger? traceLogger,
    ScheduleSanityChecker? sanityChecker,
    SyncSafetyGuard? safetyGuard,
    FacilitySyncLogger? facilitySyncLogger,
    FacilityDiscoveryService? discoveryService,
  })  : _facilityRepo = facilityRepo,
        _scheduleRepo = scheduleRepo,
        _scrapeLogRepo = scrapeLogRepo,
        _syncLogRepo = syncLogRepo,
        _tieredFetcher = tieredFetcher ??
            TieredFacilityPageFetcher(httpClient: httpClient),
        _traceLogger = traceLogger ?? ScheduleTraceLogger(),
        _sanityChecker = sanityChecker ?? ScheduleSanityChecker(),
        _safetyGuard = safetyGuard ?? SyncSafetyGuard(),
        _facilitySyncLogger = facilitySyncLogger ?? FacilitySyncLogger(),
        _discovery = discoveryService ??
            FacilityDiscoveryService(
              fetcher: tieredFetcher ??
                  TieredFacilityPageFetcher(httpClient: httpClient),
            );

  final FacilityRepository _facilityRepo;
  final ScheduleRepository _scheduleRepo;
  final ScrapeLogRepository _scrapeLogRepo;
  final SyncLogRepository? _syncLogRepo;
  final TieredFacilityPageFetcher _tieredFetcher;
  final ScheduleTraceLogger _traceLogger;
  final ScheduleSanityChecker _sanityChecker;
  final SyncSafetyGuard _safetyGuard;
  final FacilitySyncLogger _facilitySyncLogger;
  final FacilityDiscoveryService _discovery;

  FacilityDiscoveryService get discoveryService => _discovery;

  FacilitySyncLogger get facilitySyncLogger => _facilitySyncLogger;

  late final ScheduleParser _parser = ScheduleParser(
    onDroppedTime: (facilityId, category, cell, reason) =>
        _traceLogger.logDroppedTimeCell(
      facilityId: facilityId,
      rawCategory: category,
      cellText: cell,
      reason: reason,
    ),
  );

  /// @deprecated Use [BlockedPageDetector.isBlockedPage].
  static bool isBlockedPage(String html) =>
      BlockedPageDetector.isBlockedPage(html);

  static String htmlFingerprint(String html) {
    final slice = html.length > 2000 ? html.substring(0, 2000) : html;
    return sha256.convert(utf8.encode(slice)).toString().substring(0, 16);
  }

  Future<void> syncFacilityCatalog() async {
    final canonical = await _discovery.loadCanonicalFacilities();
    final discovered = await _discovery.discoverIndoorPoolsFromSource();
    final existingList = await _facilityRepo.getAllFacilities();
    final existing = {for (final f in existingList) f.id: f};
    final canonicalById = {for (final f in canonical) f.id: f};

    final toUpsert = <String, Facility>{};

    for (final row in discovered) {
      final canonicalRow = canonicalById[row.slug];
      final prev = existing[row.slug];
      var merged = _discovery.mergeDiscoveredWithCanonical(
        discovered: row,
        canonical: canonicalRow,
      );
      if (prev != null) {
        merged = merged.copyWith(
          contentHash: prev.contentHash,
          lastUpdated: prev.lastUpdated,
          lastSuccessfulSyncAt: prev.lastSuccessfulSyncAt,
          syncStatus: prev.syncStatus,
          isFavorite: prev.isFavorite,
        );
      }
      toUpsert[row.slug] = merged;
    }

    for (final c in canonical) {
      if (toUpsert.containsKey(c.id)) continue;
      final prev = existing[c.id];
      toUpsert[c.id] = prev != null
          ? c.copyWith(
              contentHash: prev.contentHash,
              lastUpdated: prev.lastUpdated,
              lastSuccessfulSyncAt: prev.lastSuccessfulSyncAt,
              syncStatus: prev.syncStatus,
              isFavorite: prev.isFavorite,
            )
          : c;
    }

    for (final facility in toUpsert.values) {
      await _facilityRepo.upsertFacility(facility);
    }

    appLogger.i(
      '[catalog] Synced ${toUpsert.length} facilities '
      '(${discovered.length} from source, ${canonical.length} canonical)',
    );
  }

  @Deprecated('Use syncFacilityCatalog')
  Future<void> seedFacilitiesIfEmpty() async {
    final existing = await _facilityRepo.getAllFacilities();
    if (existing.isNotEmpty) return;
    await syncFacilityCatalog();
  }

  Future<SyncResult> syncAll({
    bool force = false,
    SyncProgressCallback? onProgress,
  }) async {
    await syncFacilityCatalog();
    _facilitySyncLogger.clear();

    final allFacilities = await _facilityRepo.getAllFacilities();
    final facilities =
        allFacilities.where((f) => f.hasSwimSchedule).toList();
    final syncStartedAt = DateTime.now().millisecondsSinceEpoch;
    final today = OttawaTime.todayDate();
    final scheduleCountBefore = await _scheduleRepo.countAllSchedules();

    var updated = 0;
    var skipped = 0;
    var blocked = 0;
    var parseEmpty = 0;
    var parseRejected = 0;
    var networkFailures = 0;
    var pipelineCrashes = 0;
    var staleCount = 0;
    var http403Count = 0;

    final systemFailedNames = <String>[];
    final staleNames = <String>[];
    final blockedNames = <String>[];
    final parseEmptyNames = <String>[];

    void reportProgress({
      required SyncPhase phase,
      String? currentName,
      int pending = 0,
    }) {
      onProgress?.call(
        SyncProgress(
          totalFacilities: facilities.length,
          updated: updated,
          blocked: blocked,
          pending: pending,
          failed: networkFailures + pipelineCrashes + parseRejected,
          currentFacilityName: currentName,
          phase: phase,
        ),
      );
    }

    reportProgress(phase: SyncPhase.fetching, pending: facilities.length);

    final phaseResults = <_FacilityPhaseResult>[];

    for (var i = 0; i < facilities.length; i++) {
      final facility = facilities[i];
      reportProgress(
        phase: SyncPhase.fetching,
        currentName: facility.name,
        pending: facilities.length - i - 1,
      );

      final result = await _fetchAndParseFacility(
        facility: facility,
        force: force,
        today: today,
      );
      phaseResults.add(result);
      _facilitySyncLogger.record(result.diagnostic);

      switch (result.fetchOutcome) {
        case FacilityFetchOutcome.unchanged:
          skipped++;
        case FacilityFetchOutcome.blocked:
          blocked++;
          blockedNames.add(facility.name);
          if (result.existingCount > 0) staleNames.add(facility.name);
        case FacilityFetchOutcome.staleCached:
          skipped++;
          if (result.existingCount > 0) staleNames.add(facility.name);
        case FacilityFetchOutcome.parseEmpty:
          parseEmpty++;
          parseEmptyNames.add(facility.name);
          if (result.existingCount > 0) staleNames.add(facility.name);
        case FacilityFetchOutcome.parseFailure:
          parseRejected++;
          if (result.existingCount > 0) staleNames.add(facility.name);
        case FacilityFetchOutcome.httpError:
          networkFailures++;
          if (result.diagnostic.httpStatus == 403) http403Count++;
          systemFailedNames.add(facility.name);
        case FacilityFetchOutcome.pipelineCrash:
          pipelineCrashes++;
          systemFailedNames.add(facility.name);
        case FacilityFetchOutcome.success:
          break;
      }
    }

    reportProgress(phase: SyncPhase.validating, pending: 0);

    final commitCandidates = <_CommitCandidate>[
      for (final r in phaseResults)
        if (r.commitCandidate != null) r.commitCandidate!,
    ];

    final successCount = phaseResults.where((r) => r.countsAsSuccess).length;
    final successRate =
        facilities.isEmpty ? 1.0 : successCount / facilities.length;

    final antiCorruption = scheduleCountBefore > 0 &&
        facilities.isNotEmpty &&
        successRate < SyncThresholds.minGlobalSuccessRate;

    if (antiCorruption) {
      appLogger.w(
        '[sync] Anti-corruption: success rate ${(successRate * 100).toStringAsFixed(0)}% '
        'below ${(SyncThresholds.minGlobalSuccessRate * 100).toStringAsFixed(0)}% '
        '— preserving all existing data',
      );
    }

    reportProgress(phase: SyncPhase.committing, pending: 0);

    if (!antiCorruption) {
      for (final candidate in commitCandidates) {
        await _commitFacility(candidate, today);
        updated++;
        reportProgress(phase: SyncPhase.committing);
      }
    }

    for (final result in phaseResults) {
      if (result.commitCandidate != null && !antiCorruption) continue;
      await _applyFacilitySyncMetadata(result, antiCorruption: antiCorruption);
      if (result.existingCount > 0 &&
          result.fetchOutcome != FacilityFetchOutcome.success &&
          result.fetchOutcome != FacilityFetchOutcome.unchanged) {
        staleCount++;
      }
    }

    final scheduleCountAfter = await _scheduleRepo.countAllSchedules();

    _facilitySyncLogger.logRunSummary(
      total: facilities.length,
      updated: updated,
      blocked: blocked,
      parseEmpty: parseEmpty,
      systemFailures: networkFailures + pipelineCrashes,
    );

    final syncStatus = SyncStatus.fromCounts(
      totalFacilities: facilities.length,
      updated: updated,
      skipped: skipped,
      blocked: blocked,
      parseEmpty: parseEmpty,
      parseRejected: parseRejected,
      networkFailures: networkFailures,
      pipelineCrashes: pipelineCrashes,
      antiCorruptionTriggered: antiCorruption,
      scheduleCountAfter: scheduleCountAfter,
    );

    final rootCause = _summarizeRootCause(
      blocked: blocked,
      parseEmpty: parseEmpty,
      networkFailures: networkFailures,
      pipelineCrashes: pipelineCrashes,
      total: facilities.length,
      scheduleCountAfter: scheduleCountAfter,
    );

    final completedAt = DateTime.now().millisecondsSinceEpoch;
    final message = antiCorruption
        ? 'Anti-corruption: success rate ${(successRate * 100).toStringAsFixed(0)}% — kept previous data'
        : rootCause;

    await _syncLogRepo?.insertLog(
      SyncLogEntry(
        startedAt: syncStartedAt,
        completedAt: completedAt,
        status: syncStatus,
        successRate: successRate,
        facilitiesTotal: facilities.length,
        facilitiesUpdated: updated,
        facilitiesSkipped: skipped,
        facilitiesBlocked: blocked,
        facilitiesFailed:
            networkFailures + pipelineCrashes + parseRejected + parseEmpty,
        facilitiesStale: staleCount,
        scheduleCountBefore: scheduleCountBefore,
        scheduleCountAfter: scheduleCountAfter,
        message: message,
        antiCorruptionTriggered: antiCorruption,
      ),
    );

    return SyncResult(
      syncStatus: syncStatus,
      updated: updated,
      skipped: skipped,
      errors: networkFailures,
      rejected: parseRejected,
      blocked: blocked,
      parseEmpty: parseEmpty,
      pipelineCrashes: pipelineCrashes,
      staleCount: staleCount,
      http403Count: http403Count,
      scheduleCountBefore: scheduleCountBefore,
      scheduleCountAfter: scheduleCountAfter,
      totalFacilities: allFacilities.length,
      antiCorruptionTriggered: antiCorruption,
      antiCorruptionReason: antiCorruption ? message : null,
      rootCauseSummary: rootCause,
      facilitiesParsed: successCount,
      successRate: successRate,
      projectedFutureSessions: await _scheduleRepo.countFutureSessions(today),
      failedFacilityNames: systemFailedNames,
      staleFacilityNames: staleNames.toSet().toList(),
      blockedFacilityNames: blockedNames,
      parseEmptyFacilityNames: parseEmptyNames,
      facilityDiagnostics: List.unmodifiable(_facilitySyncLogger.lastRunDiagnostics),
    );
  }

  String _summarizeRootCause({
    required int blocked,
    required int parseEmpty,
    required int networkFailures,
    required int pipelineCrashes,
    required int total,
    required int scheduleCountAfter,
  }) {
    if (blocked == total) {
      return 'ROOT CAUSE: BOT/BLOCK — ottawa.ca returned challenge pages for all '
          '$total facilities. Network works; schedules are blocked, not missing. '
          'Cached data preserved: $scheduleCountAfter sessions.';
    }
    if (blocked > 0 && networkFailures == 0 && pipelineCrashes == 0) {
      return 'ROOT CAUSE: PARTIAL BOT BLOCK — $blocked/$total facilities blocked by '
          'ottawa.ca challenge pages. Valid facilities still sync. '
          'Cached data preserved: $scheduleCountAfter sessions.';
    }
    if (networkFailures > 0) {
      return 'ROOT CAUSE: NETWORK — $networkFailures facility fetch(es) failed at HTTP level.';
    }
    if (parseEmpty > 0) {
      return 'ROOT CAUSE: PARSE_EMPTY — $parseEmpty facility page(s) loaded but parser '
          'found 0 sessions.';
    }
    if (pipelineCrashes > 0) {
      return 'ROOT CAUSE: PIPELINE_CRASH — $pipelineCrashes unexpected exception(s).';
    }
    return 'Sync completed normally.';
  }

  Future<_FacilityPhaseResult> _fetchAndParseFacility({
    required Facility facility,
    required bool force,
    required String today,
  }) async {
    final start = DateTime.now();
    final existingCount =
        await _scheduleRepo.countSchedulesForFacility(facility.id);
    final requestUrl = facility.url ??
        'https://ottawa.ca/en/recreation-and-parks/facilities/place-listing/${facility.id}';

    FacilitySyncDiagnostic diagnostic({
      required FacilitySyncFailureKind kind,
      int? httpStatus,
      String? finalUrl,
      String? contentType,
      String? blockedSummary,
      String? fingerprint,
      int sessionsParsed = 0,
      int swimMentions = 0,
      String? detail,
      String? fetchTier,
      String? tierTrail,
    }) {
      return FacilitySyncDiagnostic(
        facilityId: facility.id,
        facilityName: facility.name,
        kind: kind,
        httpStatus: httpStatus,
        requestUrl: requestUrl,
        finalUrl: finalUrl,
        contentType: contentType,
        blockedCheckSummary: blockedSummary,
        htmlFingerprint: fingerprint,
        sessionsParsed: sessionsParsed,
        swimMentions: swimMentions,
        existingCachedSessions: existingCount,
        detail: detail,
        fetchTier: fetchTier,
        tierTrail: tierTrail,
      );
    }

    try {
      final fetch = await _tieredFetcher.fetch(
        url: requestUrl,
        facilityId: facility.id,
        existingCachedSessions: existingCount,
      );
      final durationMs = DateTime.now().difference(start).inMilliseconds;
      final tierTrail = fetch.tierTrail;

      if (fetch.outcome == TieredFetchOutcome.staleCached) {
        final diag = diagnostic(
          kind: FacilitySyncFailureKind.cachedFallback,
          httpStatus: fetch.httpStatus,
          sessionsParsed: existingCount,
          detail: fetch.errorMessage ?? 'Using cached DB schedules',
          fetchTier: FacilityFetchTier.cacheDb.label,
          tierTrail: tierTrail,
        );
        await _logScrape(
          facilityId: facility.id,
          status: 'stale_cached',
          message: diag.logMessage(),
          durationMs: durationMs,
        );
        return _FacilityPhaseResult(
          facility: facility,
          fetchOutcome: FacilityFetchOutcome.staleCached,
          validationClass: FacilityValidationClass.valid,
          existingCount: existingCount,
          diagnostic: diag,
          durationMs: durationMs,
          countsAsSuccess: true,
        );
      }

      if (fetch.outcome == TieredFetchOutcome.blocked) {
        final diag = diagnostic(
          kind: FacilitySyncFailureKind.blockedBotChallenge,
          httpStatus: fetch.httpStatus ?? 200,
          detail: fetch.errorMessage ?? tierTrail,
          fetchTier: 'BLOCKED_ALL_TIERS',
          tierTrail: tierTrail,
        );
        await _logScrape(
          facilityId: facility.id,
          status: 'blocked',
          message: diag.logMessage(),
          durationMs: durationMs,
        );
        return _FacilityPhaseResult(
          facility: facility,
          fetchOutcome: FacilityFetchOutcome.blocked,
          validationClass: FacilityValidationClass.failed,
          existingCount: existingCount,
          diagnostic: diag,
          durationMs: durationMs,
        );
      }

      if (fetch.outcome == TieredFetchOutcome.httpError) {
        final status = fetch.httpStatus ?? 0;
        final kind = status == 403
            ? FacilitySyncFailureKind.blockedBotChallenge
            : FacilitySyncFailureKind.networkFailure;
        final diag = diagnostic(
          kind: kind,
          httpStatus: status == 0 ? null : status,
          detail: fetch.errorMessage,
          tierTrail: tierTrail,
        );
        await _logScrape(
          facilityId: facility.id,
          status: kind == FacilitySyncFailureKind.blockedBotChallenge
              ? 'blocked'
              : 'error',
          message: diag.logMessage(),
          durationMs: durationMs,
        );
        return _FacilityPhaseResult(
          facility: facility,
          fetchOutcome: status == 403
              ? FacilityFetchOutcome.blocked
              : FacilityFetchOutcome.httpError,
          validationClass: FacilityValidationClass.failed,
          existingCount: existingCount,
          diagnostic: diag,
          durationMs: durationMs,
        );
      }

      final page = fetch.page!;
      final response = toHttpResponse(page);
      final html = response.body;
      final hash = sha256.convert(utf8.encode(html)).toString();
      final fingerprint = htmlFingerprint(html);
      final contentType = response.headers['content-type'];
      final finalUrl = response.request?.url.toString();
      final fetchTierLabel = page.tier.label;

      if (!force && facility.contentHash == hash) {
        final diag = diagnostic(
          kind: FacilitySyncFailureKind.unchanged,
          httpStatus: response.statusCode,
          finalUrl: finalUrl,
          contentType: contentType,
          fingerprint: fingerprint,
          sessionsParsed: existingCount,
          fetchTier: fetchTierLabel,
          tierTrail: tierTrail,
        );
        await _logScrape(
          facilityId: facility.id,
          status: 'skipped',
          message: diag.logMessage(),
          contentHash: hash,
          durationMs: durationMs,
        );
        return _FacilityPhaseResult(
          facility: facility,
          fetchOutcome: FacilityFetchOutcome.unchanged,
          validationClass: FacilityValidationClass.valid,
          existingCount: existingCount,
          diagnostic: diag,
          durationMs: durationMs,
          countsAsSuccess: true,
        );
      }

      // Hard block check BEFORE parser — never parse challenge HTML.
      final blockedCheck = BlockedPageDetector.check(html);
      if (blockedCheck.isBlocked) {
        final diag = diagnostic(
          kind: FacilitySyncFailureKind.blockedBotChallenge,
          httpStatus: response.statusCode,
          finalUrl: finalUrl,
          contentType: contentType,
          blockedSummary: blockedCheck.summary,
          fingerprint: fingerprint,
          detail: blockedCheck.signaturesMatched.join(', '),
          fetchTier: fetchTierLabel,
          tierTrail: tierTrail,
        );
        await _logScrape(
          facilityId: facility.id,
          status: 'blocked',
          message: diag.logMessage(),
          durationMs: durationMs,
          contentHash: fingerprint,
        );
        return _FacilityPhaseResult(
          facility: facility,
          fetchOutcome: FacilityFetchOutcome.blocked,
          validationClass: FacilityValidationClass.failed,
          existingCount: existingCount,
          diagnostic: diag,
          durationMs: durationMs,
        );
      }

      final snapshotPath = page.tier == FacilityFetchTier.cacheSnapshot
          ? null
          : await _saveSnapshot(facility.id, html);
      _traceLogger.logParseStart(
        facilityId: facility.id,
        htmlLength: html.length,
        snapshotPath: snapshotPath,
      );

      final (entries, tableInfos) =
          _parser.parseWithTableInfo(html, facility.id);
      final swimMentions = ScheduleSanityChecker.countSwimMentions(html);

      _traceLogger.logParsedEntries(
        facilityId: facility.id,
        entries: entries,
        today: today,
      );

      if (entries.isEmpty) {
        final diag = diagnostic(
          kind: FacilitySyncFailureKind.parseEmpty,
          httpStatus: response.statusCode,
          finalUrl: finalUrl,
          contentType: contentType,
          blockedSummary: blockedCheck.summary,
          fingerprint: fingerprint,
          swimMentions: swimMentions,
          detail: 'Parser returned 0 sessions; swimMentions=$swimMentions',
          fetchTier: fetchTierLabel,
          tierTrail: tierTrail,
        );
        await _logScrape(
          facilityId: facility.id,
          status: 'parse_empty',
          message: diag.logMessage(),
          htmlSnapshotPath: snapshotPath,
          contentHash: hash,
          durationMs: durationMs,
        );
        return _FacilityPhaseResult(
          facility: facility,
          fetchOutcome: FacilityFetchOutcome.parseEmpty,
          validationClass: FacilityValidationClass.failed,
          existingCount: existingCount,
          entries: entries,
          hash: hash,
          snapshotPath: snapshotPath,
          diagnostic: diag,
          durationMs: durationMs,
        );
      }

      final sanity = _sanityChecker.check(
        facilityId: facility.id,
        facilityName: facility.name,
        entries: entries,
        htmlSwimMentions: swimMentions,
        tables: tableInfos,
      );

      final decision = _safetyGuard.evaluate(
        facilityId: facility.id,
        newEntries: entries,
        existingEntryCount: existingCount,
        htmlSwimMentions: swimMentions,
        httpStatus: response.statusCode,
      );

      if (!decision.allowWrite) {
        final diag = diagnostic(
          kind: FacilitySyncFailureKind.parseRejected,
          httpStatus: response.statusCode,
          finalUrl: finalUrl,
          contentType: contentType,
          blockedSummary: blockedCheck.summary,
          fingerprint: fingerprint,
          sessionsParsed: entries.length,
          swimMentions: swimMentions,
          detail: decision.reason,
          fetchTier: fetchTierLabel,
          tierTrail: tierTrail,
        );
        await _logScrape(
          facilityId: facility.id,
          status: 'parse_rejected',
          message: diag.logMessage(),
          htmlSnapshotPath: snapshotPath,
          contentHash: hash,
          durationMs: durationMs,
        );
        return _FacilityPhaseResult(
          facility: facility,
          fetchOutcome: FacilityFetchOutcome.parseFailure,
          validationClass: FacilityValidationClass.failed,
          existingCount: existingCount,
          entries: entries,
          hash: hash,
          snapshotPath: snapshotPath,
          rejectReason: decision.reason,
          diagnostic: diag,
          durationMs: durationMs,
        );
      }

      final validationClass = sanity.hasIssues
          ? FacilityValidationClass.partial
          : FacilityValidationClass.valid;
      final sanityNote =
          sanity.hasIssues ? ' sanityWarnings=${sanity.warnings.length}' : '';

      final diag = diagnostic(
        kind: FacilitySyncFailureKind.ok,
        httpStatus: response.statusCode,
        finalUrl: finalUrl,
        contentType: contentType,
        blockedSummary: blockedCheck.summary,
        fingerprint: fingerprint,
        sessionsParsed: entries.length,
        swimMentions: swimMentions,
        fetchTier: fetchTierLabel,
        tierTrail: tierTrail,
      );

      return _FacilityPhaseResult(
        facility: facility,
        fetchOutcome: FacilityFetchOutcome.success,
        validationClass: validationClass,
        existingCount: existingCount,
        entries: entries,
        hash: hash,
        snapshotPath: snapshotPath,
        diagnostic: diag,
        durationMs: durationMs,
        countsAsSuccess: true,
        commitCandidate: _CommitCandidate(
          facility: facility,
          entries: entries,
          hash: hash,
          snapshotPath: snapshotPath,
          existingCount: existingCount,
          durationMs: durationMs,
          validationClass: validationClass,
          sanityNote: sanityNote,
        ),
      );
    } catch (e, st) {
      appLogger.e('Pipeline crash for ${facility.id}', error: e, stackTrace: st);
      final diag = diagnostic(
        kind: FacilitySyncFailureKind.pipelineCrash,
        detail: e.toString(),
      );
      await _logScrape(
        facilityId: facility.id,
        status: 'pipeline_crash',
        message: diag.logMessage(),
        durationMs: DateTime.now().difference(start).inMilliseconds,
      );
      return _FacilityPhaseResult(
        facility: facility,
        fetchOutcome: FacilityFetchOutcome.pipelineCrash,
        validationClass: FacilityValidationClass.failed,
        existingCount: existingCount,
        diagnostic: diag,
      );
    }
  }

  Future<String> _saveSnapshot(String facilityId, String html) async {
    final dir = await getApplicationDocumentsDirectory();
    final snapshotsDir = Directory('${dir.path}/snapshots');
    if (!await snapshotsDir.exists()) {
      await snapshotsDir.create(recursive: true);
    }
    final path =
        '${snapshotsDir.path}/${facilityId}_${DateTime.now().millisecondsSinceEpoch}.html';
    await File(path).writeAsString(html);
    return path;
  }

  Future<void> _logScrape({
    required String facilityId,
    required String status,
    required String message,
    int? durationMs,
    String? htmlSnapshotPath,
    String? contentHash,
  }) {
    return _scrapeLogRepo.insertLog(ScrapeLog(
      facilityId: facilityId,
      status: status,
      message: message,
      htmlSnapshotPath: htmlSnapshotPath,
      contentHash: contentHash,
      durationMs: durationMs,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<void> _commitFacility(_CommitCandidate candidate, String today) async {
    await _scheduleRepo.deleteSchedulesForFacility(candidate.facility.id);
    await _scheduleRepo.upsertSchedules(
      candidate.facility.id,
      candidate.entries,
    );

    final storedToday =
        candidate.entries.where((e) => e.date == today).length;
    _traceLogger.logStoredEntries(
      facilityId: candidate.facility.id,
      storedCount: candidate.entries.length,
      todayCount: storedToday,
    );

    final now = DateTime.now().millisecondsSinceEpoch;
    await _facilityRepo.upsertFacility(
      candidate.facility.copyWith(
        contentHash: candidate.hash,
        lastUpdated: now,
        lastSuccessfulSyncAt: now,
        syncStatus: FacilitySyncStatus.ok,
      ),
    );

    await _logScrape(
      facilityId: candidate.facility.id,
      status: 'success',
      message:
          '${candidate.entries.length} entries ($storedToday today)${candidate.sanityNote}',
      htmlSnapshotPath: candidate.snapshotPath,
      contentHash: candidate.hash,
      durationMs: candidate.durationMs,
    );
  }

  Future<void> _applyFacilitySyncMetadata(
    _FacilityPhaseResult result, {
    required bool antiCorruption,
  }) async {
    final f = result.facility;

    if (result.fetchOutcome == FacilityFetchOutcome.unchanged) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _facilityRepo.updateSyncMetadata(
        facilityId: f.id,
        syncStatus: FacilitySyncStatus.ok,
        lastSuccessfulSyncAt: f.lastSuccessfulSyncAt ?? now,
      );
      return;
    }

    if (antiCorruption && result.commitCandidate != null) return;

    if (result.fetchOutcome == FacilityFetchOutcome.staleCached) {
      await _facilityRepo.updateSyncMetadata(
        facilityId: f.id,
        syncStatus: FacilitySyncStatus.stale,
        lastSuccessfulSyncAt: f.lastSuccessfulSyncAt,
      );
      return;
    }

    if (result.fetchOutcome == FacilityFetchOutcome.blocked ||
        result.fetchOutcome == FacilityFetchOutcome.parseEmpty ||
        result.fetchOutcome == FacilityFetchOutcome.parseFailure) {
      await _facilityRepo.updateSyncMetadata(
        facilityId: f.id,
        syncStatus: result.existingCount > 0
            ? FacilitySyncStatus.stale
            : FacilitySyncStatus.failed,
      );
      return;
    }

    if (result.fetchOutcome == FacilityFetchOutcome.httpError ||
        result.fetchOutcome == FacilityFetchOutcome.pipelineCrash) {
      await _facilityRepo.updateSyncMetadata(
        facilityId: f.id,
        syncStatus: result.existingCount > 0
            ? FacilitySyncStatus.stale
            : FacilitySyncStatus.failed,
      );
    }
  }
}

class SyncResult {
  const SyncResult({
    required this.syncStatus,
    required this.updated,
    required this.skipped,
    required this.errors,
    this.rejected = 0,
    this.blocked = 0,
    this.parseEmpty = 0,
    this.pipelineCrashes = 0,
    this.staleCount = 0,
    this.http403Count = 0,
    this.scheduleCountBefore = 0,
    this.scheduleCountAfter = 0,
    this.totalFacilities = 0,
    this.antiCorruptionTriggered = false,
    this.antiCorruptionReason,
    this.rootCauseSummary,
    this.facilitiesParsed = 0,
    this.successRate = 1.0,
    this.projectedFutureSessions = 0,
    this.failedFacilityNames = const [],
    this.staleFacilityNames = const [],
    this.blockedFacilityNames = const [],
    this.parseEmptyFacilityNames = const [],
    this.facilityDiagnostics = const [],
  });

  final SyncStatus syncStatus;
  final int updated;
  final int skipped;
  final int errors;
  final int rejected;
  final int blocked;
  final int parseEmpty;
  final int pipelineCrashes;
  final int staleCount;
  final int http403Count;
  final int scheduleCountBefore;
  final int scheduleCountAfter;
  final int totalFacilities;
  final bool antiCorruptionTriggered;
  final String? antiCorruptionReason;
  final String? rootCauseSummary;
  final int facilitiesParsed;
  final double successRate;
  final int projectedFutureSessions;
  final List<String> failedFacilityNames;
  final List<String> staleFacilityNames;
  final List<String> blockedFacilityNames;
  final List<String> parseEmptyFacilityNames;
  final List<FacilitySyncDiagnostic> facilityDiagnostics;

  bool get globalRejected => antiCorruptionTriggered;
  String? get globalRejectReason => antiCorruptionReason;
  bool get success => syncStatus == SyncStatus.success;
  bool get isHealthy =>
      !antiCorruptionTriggered &&
      (scheduleCountAfter > 0 ||
          (scheduleCountAfter >= scheduleCountBefore && errors < totalFacilities));

  String get statusLabel => switch (syncStatus) {
        SyncStatus.success => 'success',
        SyncStatus.partialSuccess => 'partial',
        SyncStatus.failed => 'failed',
      };

  bool get isMostlyBlocked =>
      blocked > 0 && blocked >= (totalFacilities * 0.5).ceil();

  bool get isFirstInstallBlocked =>
      scheduleCountAfter == 0 && blocked > 0 && errors == 0;
}
