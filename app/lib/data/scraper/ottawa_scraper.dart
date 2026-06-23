import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/sync_rate_limit_policy.dart';
import '../../core/constants/sync_thresholds.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/ottawa_time.dart';
import '../../domain/entities/sync_result.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/facility_fetch_tier.dart';
import '../../domain/entities/facility_priority.dart';
import '../../domain/entities/sync_location_context.dart';
import '../../domain/entities/facility_type.dart';
import '../../domain/entities/facility_sync_diagnostic.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/entities/scrape_log.dart';
import '../../domain/entities/sync_log.dart';
import '../../domain/entities/sync_progress.dart';
import '../../domain/entities/schedule_trust_status.dart';
import '../../domain/entities/sync_engine_mode.dart';
import '../../domain/entities/sync_status.dart';
import '../../domain/repositories/repositories.dart';
import '../services/blocked_page_detector.dart';
import '../services/facility_backoff_tracker.dart';
import '../services/facility_discovery_service.dart';
import '../services/facility_sync_logger.dart';
import '../services/fetch/playwright_sync_service.dart';
import '../services/fetch/tiered_facility_page_fetcher.dart';
import '../services/ottawa_http_client.dart';
import '../services/partial_refresh_planner.dart';
import '../services/smart_sync_queue.dart';
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
    FacilityBackoffTracker? backoffTracker,
    SettingsRepository? settingsRepo,
    SmartSyncQueue? smartSyncQueue,
    PartialRefreshPlanner? refreshPlanner,
    PlaywrightSyncService? playwrightSync,
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
              httpClient: httpClient,
            ),
        _backoffTracker = backoffTracker,
        _settingsRepo = settingsRepo,
        _smartSyncQueue = smartSyncQueue,
        _refreshPlanner = refreshPlanner ?? const PartialRefreshPlanner(),
        _playwrightSync = playwrightSync;

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
  final FacilityBackoffTracker? _backoffTracker;
  final SettingsRepository? _settingsRepo;
  final SmartSyncQueue? _smartSyncQueue;
  final PartialRefreshPlanner _refreshPlanner;
  final PlaywrightSyncService? _playwrightSync;

  Future<SyncEngineMode> _syncEngineMode() async {
    if (_settingsRepo == null) return SyncEngineMode.browserPrimary;
    final raw = await _settingsRepo!.getString(AppConstants.settingsSyncEngineMode);
    return SyncEngineMode.fromStorage(raw);
  }

  Future<bool> _playwrightDebugMode() async {
    if (_settingsRepo == null) return false;
    return _settingsRepo!.getBool(AppConstants.settingsPlaywrightDebugMode);
  }

  FacilityRepository get facilityRepo => _facilityRepo;

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

  Future<void> syncFacilityCatalog({bool force = false}) async {
    final existingList = await _facilityRepo.getAllFacilities();
    if (_settingsRepo != null && !force && existingList.isNotEmpty) {
      final lastCatalogSync = await _settingsRepo!.getString(
        AppConstants.settingsLastCatalogSyncAt,
      );
      final lastMs = int.tryParse(lastCatalogSync ?? '') ?? 0;
      final hoursSince =
          (DateTime.now().millisecondsSinceEpoch - lastMs) / (1000 * 60 * 60);
      if (hoursSince < SyncRateLimitPolicy.catalogRefreshIntervalHours) {
        appLogger.i(
          '[catalog] Skipping live discovery — last refresh '
          '${hoursSince.toStringAsFixed(1)}h ago',
        );
        return;
      }
    }

    final canonical = await _discovery.loadCanonicalFacilities();
    final syncEngine = await _syncEngineMode();
    final useBrowser = syncEngine.isBrowserPrimary;
    final discovered = await _discovery.discoverIndoorPoolsFromSource(
      escalateToBrowser: useBrowser,
    );
    final outdoorDiscovered = await _discovery.discoverOutdoorPoolsFromSource(
      escalateToBrowser: useBrowser,
    );
    final existing = {for (final f in existingList) f.id: f};
    final canonicalById = {for (final f in canonical) f.id: f};

    final toUpsert = <String, Facility>{};

    for (final row in [...discovered, ...outdoorDiscovered]) {
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
      '(${discovered.length} indoor, ${outdoorDiscovered.length} outdoor, '
      '${canonical.length} canonical)',
    );

    if (_settingsRepo != null) {
      await _settingsRepo!.setString(
        AppConstants.settingsLastCatalogSyncAt,
        DateTime.now().millisecondsSinceEpoch.toString(),
      );
    }
  }

  @Deprecated('Use syncFacilityCatalog')
  Future<void> seedFacilitiesIfEmpty() async {
    final existing = await _facilityRepo.getAllFacilities();
    if (existing.isNotEmpty) return;
    await syncFacilityCatalog();
  }

  Future<SyncResult> syncAll({
    bool force = false,
    bool isOnboarding = false,
    SmartSyncPhase phase = SmartSyncPhase.background,
    SyncLocationContext? anchor,
    SyncProgressCallback? onProgress,
  }) async {
    await syncFacilityCatalog(force: force && isOnboarding);
    _facilitySyncLogger.clear();

    final syncEngine = await _syncEngineMode();
    var browserSessionStarted = false;
    if (syncEngine.isBrowserPrimary && _playwrightSync?.isAvailable == true) {
      browserSessionStarted = await _playwrightSync!.startSession(
        headless: !(await _playwrightDebugMode()),
      );
      if (browserSessionStarted) {
        appLogger.i('[sync] Playwright browser session started');
      }
    }

    try {
    return await _syncAllBody(
      force: force,
      isOnboarding: isOnboarding,
      phase: phase,
      anchor: anchor,
      onProgress: onProgress,
      syncEngine: syncEngine,
    );
    } finally {
      if (browserSessionStarted) {
        await _playwrightSync?.endSession();
        appLogger.i('[sync] Playwright browser session closed');
      }
      if (_settingsRepo != null) {
        final engineLabel = syncEngine.isBrowserPrimary
            ? _tieredFetcher.browserFetcher.engineLabel
            : 'HTTP';
        await _settingsRepo!.setString(
          AppConstants.settingsLastSyncEngine,
          engineLabel,
        );
      }
    }
  }

  Future<SyncResult> _syncAllBody({
    required bool force,
    required bool isOnboarding,
    required SmartSyncPhase phase,
    SyncLocationContext? anchor,
    SyncProgressCallback? onProgress,
    required SyncEngineMode syncEngine,
  }) async {
    final allFacilities = await _facilityRepo.getAllFacilities();
    final facilities =
        allFacilities.where((f) => f.hasSwimSchedule).toList();
    final staleThresholdHours = await _staleThresholdHours();
    final rotationIndex = await _rotationIndex();
    final locationAnchor = anchor ?? SyncLocationContext.fallback();

    final backoffIds = <String>{};
    if (_backoffTracker != null) {
      for (final facility in facilities) {
        if (await _backoffTracker!.isInBackoff(facility.id)) {
          backoffIds.add(facility.id);
        }
      }
    }

    final List<Facility> refreshTargets;
    if (_smartSyncQueue != null) {
      final batch = await _smartSyncQueue!.planBatch(
        facilities: facilities,
        phase: phase,
        anchor: locationAnchor,
        force: force,
        staleThresholdHours: staleThresholdHours,
        backoffFacilityIds: backoffIds,
        rotationIndex: rotationIndex,
      );
      refreshTargets = facilities
          .where((f) => batch.facilityIds.contains(f.id))
          .toList()
        ..sort((a, b) =>
            batch.facilityIds.indexOf(a.id).compareTo(batch.facilityIds.indexOf(b.id)));

      if (_settingsRepo != null && batch.facilityIds.isNotEmpty) {
        final eligible = facilities.where((f) {
          if (backoffIds.contains(f.id)) return false;
          if (force) return true;
          return !_isFacilityFresh(f, staleThresholdHours);
        }).length;
        final nextIndex = _smartSyncQueue!.nextRotationIndex(
          currentIndex: rotationIndex,
          selectedCount: batch.facilityIds.length,
          eligibleCount: eligible > 0 ? eligible : batch.facilityIds.length,
        );
        await _settingsRepo!.setString(
          AppConstants.settingsSyncRotationIndex,
          nextIndex.toString(),
        );
      }

      appLogger.i(
        '[sync] Smart ${phase.name}: ${refreshTargets.length}/${facilities.length} '
        'facilities queued (anchor=${locationAnchor.usesDeviceLocation ? "gps" : "fallback"}, '
        'stale>${staleThresholdHours}h, backoff=${backoffIds.length})',
      );
    } else {
      refreshTargets = _refreshPlanner.selectFacilitiesForRefresh(
        facilities: facilities,
        force: force,
        isOnboarding: isOnboarding,
        staleThresholdHours: staleThresholdHours,
        rotationIndex: rotationIndex,
        backoffFacilityIds: backoffIds,
      );
      appLogger.i(
        '[sync] Partial refresh: ${refreshTargets.length}/${facilities.length} '
        'facilities queued (stale>${staleThresholdHours}h, backoff=${backoffIds.length})',
      );
    }
    final refreshIds = refreshTargets.map((f) => f.id).toSet();
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

      final _FacilityPhaseResult result;
      if (!refreshIds.contains(facility.id)) {
        result = await _cacheOnlyFacilityResult(
          facility: facility,
          today: today,
          reason: backoffIds.contains(facility.id)
              ? 'Backoff active — skipped network fetch'
              : 'Cache fresh — skipped network fetch',
        );
      } else {
        result = await _fetchAndParseFacility(
          facility: facility,
          force: force,
          today: today,
          staleThresholdHours: staleThresholdHours,
          syncEngine: syncEngine,
        );
      }
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

  Future<int> _staleThresholdHours() async {
    if (_settingsRepo == null) {
      return SyncRateLimitPolicy.defaultStaleThresholdHours;
    }
    final raw = await _settingsRepo!.getString(
      AppConstants.settingsStaleThresholdHours,
    );
    final parsed = int.tryParse(raw ?? '');
    if (parsed == null) return SyncRateLimitPolicy.defaultStaleThresholdHours;
    return parsed.clamp(
      SyncRateLimitPolicy.minStaleThresholdHours,
      SyncRateLimitPolicy.maxStaleThresholdHours,
    );
  }

  Future<int> _rotationIndex() async {
    if (_settingsRepo == null) return 0;
    final raw = await _settingsRepo!.getString(
      AppConstants.settingsSyncRotationIndex,
    );
    return int.tryParse(raw ?? '') ?? 0;
  }

  bool _isFacilityFresh(Facility facility, int staleThresholdHours) {
    if (facility.syncStatus == FacilitySyncStatus.failed) return false;
    if (facility.syncStatus == FacilitySyncStatus.stale) return false;
    final lastOk = facility.lastSuccessfulSyncAt;
    if (lastOk == null) return false;
    final staleBefore = DateTime.now()
        .subtract(Duration(hours: staleThresholdHours))
        .millisecondsSinceEpoch;
    return lastOk >= staleBefore;
  }

  Future<_FacilityPhaseResult> _cacheOnlyFacilityResult({
    required Facility facility,
    required String today,
    required String reason,
  }) async {
    final existingCount =
        await _scheduleRepo.countSchedulesForFacility(facility.id);
    final kind = existingCount > 0
        ? FacilitySyncFailureKind.cachedFallback
        : FacilitySyncFailureKind.unchanged;
    final diag = FacilitySyncDiagnostic(
      facilityId: facility.id,
      facilityName: facility.name,
      kind: kind,
      sessionsParsed: existingCount,
      existingCachedSessions: existingCount,
      detail: reason,
      fetchTier: 'CACHE_ONLY',
    );
    return _FacilityPhaseResult(
      facility: facility,
      fetchOutcome: existingCount > 0
          ? FacilityFetchOutcome.staleCached
          : FacilityFetchOutcome.unchanged,
      validationClass: FacilityValidationClass.valid,
      existingCount: existingCount,
      diagnostic: diag,
      countsAsSuccess: true,
    );
  }

  Future<_FacilityPhaseResult> _fetchAndParseFacility({
    required Facility facility,
    required bool force,
    required String today,
    required int staleThresholdHours,
    required SyncEngineMode syncEngine,
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
      int? domSizeBytes,
      int? loadTimeMs,
      String? syncEngineLabel,
      int? scheduleTableCount,
      bool usedHttpFallback = false,
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
        domSizeBytes: domSizeBytes,
        loadTimeMs: loadTimeMs,
        syncEngine: syncEngineLabel,
        scheduleTableCount: scheduleTableCount,
        usedHttpFallback: usedHttpFallback,
      );
    }

    FacilityPageFetchResult? lastPage;

    try {
      if (!force && _isFacilityFresh(facility, staleThresholdHours)) {
        return _cacheOnlyFacilityResult(
          facility: facility,
          today: today,
          reason: 'Within $staleThresholdHours h freshness window',
        );
      }

      if (_backoffTracker != null &&
          await _backoffTracker!.isInBackoff(facility.id)) {
        final retryAfter = await _backoffTracker!.retryAfter(facility.id);
        return _cacheOnlyFacilityResult(
          facility: facility,
          today: today,
          reason: 'Backoff until ${retryAfter?.toIso8601String() ?? 'later'}',
        );
      }

      final fetch = await _tieredFetcher.fetch(
        url: requestUrl,
        facilityId: facility.id,
        existingCachedSessions: existingCount,
        escalateToBrowser: syncEngine.isBrowserPrimary,
        syncEngineMode: syncEngine,
      );
      final durationMs = DateTime.now().difference(start).inMilliseconds;
      final tierTrail = fetch.tierTrail;
      lastPage = fetch.page;

      int? pageDomSize() => lastPage?.domSizeBytes;
      int? pageLoadMs() => lastPage?.loadTimeMs ?? durationMs;
      String? pageEngine() => lastPage?.syncEngineLabel ??
          (syncEngine.isBrowserPrimary
              ? _tieredFetcher.browserFetcher.engineLabel
              : 'HTTP');
      int? pageTables() => lastPage?.scheduleTableCount;
      bool pageFallback() => fetch.usedHttpFallback || (lastPage?.usedHttpFallback ?? false);

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
        await _backoffTracker?.recordBlock(facility.id);
        final browserBlocked = fetch.attempts.any(
          (a) => a.tier == FacilityFetchTier.browser,
        );
        final diag = diagnostic(
          kind: existingCount > 0
              ? FacilitySyncFailureKind.cachedFallback
              : browserBlocked
                  ? FacilitySyncFailureKind.blockedPlaywright
                  : FacilitySyncFailureKind.blockedBotChallenge,
          httpStatus: fetch.httpStatus ?? 200,
          sessionsParsed: existingCount,
          detail: fetch.errorMessage ?? tierTrail,
          fetchTier: browserBlocked ? 'BLOCKED_PLAYWRIGHT' : 'BLOCKED_ALL_TIERS',
          tierTrail: tierTrail,
          domSizeBytes: pageDomSize(),
          loadTimeMs: pageLoadMs(),
          syncEngineLabel: pageEngine(),
          scheduleTableCount: pageTables(),
          usedHttpFallback: pageFallback(),
        );
        await _logScrape(
          facilityId: facility.id,
          status: 'blocked',
          message: diag.logMessage(),
          durationMs: durationMs,
        );
        return _FacilityPhaseResult(
          facility: facility,
          fetchOutcome: existingCount > 0
              ? FacilityFetchOutcome.staleCached
              : FacilityFetchOutcome.blocked,
          validationClass: FacilityValidationClass.failed,
          existingCount: existingCount,
          diagnostic: diag,
          durationMs: durationMs,
          countsAsSuccess: existingCount > 0,
        );
      }

      if (fetch.outcome == TieredFetchOutcome.httpError) {
        final status = fetch.httpStatus ?? 0;
        final isBotStatus = status == 403 || status == 429;
        if (isBotStatus) {
          await _backoffTracker?.recordBlock(facility.id);
        }
        final kind = isBotStatus
            ? (existingCount > 0
                ? FacilitySyncFailureKind.cachedFallback
                : FacilitySyncFailureKind.blockedBotChallenge)
            : FacilitySyncFailureKind.networkFailure;
        final diag = diagnostic(
          kind: kind,
          httpStatus: status == 0 ? null : status,
          sessionsParsed: existingCount,
          detail: fetch.errorMessage,
          tierTrail: tierTrail,
        );
        await _logScrape(
          facilityId: facility.id,
          status: isBotStatus ? 'blocked' : 'error',
          message: diag.logMessage(),
          durationMs: durationMs,
        );
        final outcome = isBotStatus
            ? (existingCount > 0
                ? FacilityFetchOutcome.staleCached
                : FacilityFetchOutcome.blocked)
            : (existingCount > 0
                ? FacilityFetchOutcome.staleCached
                : FacilityFetchOutcome.httpError);
        return _FacilityPhaseResult(
          facility: facility,
          fetchOutcome: outcome,
          validationClass: FacilityValidationClass.failed,
          existingCount: existingCount,
          diagnostic: diag,
          durationMs: durationMs,
          countsAsSuccess: existingCount > 0,
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
        await _backoffTracker?.recordBlock(facility.id);
        final diag = diagnostic(
          kind: existingCount > 0
              ? FacilitySyncFailureKind.cachedFallback
              : FacilitySyncFailureKind.blockedBotChallenge,
          httpStatus: response.statusCode,
          finalUrl: finalUrl,
          contentType: contentType,
          blockedSummary: blockedCheck.summary,
          fingerprint: fingerprint,
          sessionsParsed: existingCount,
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
          fetchOutcome: existingCount > 0
              ? FacilityFetchOutcome.staleCached
              : FacilityFetchOutcome.blocked,
          validationClass: FacilityValidationClass.failed,
          existingCount: existingCount,
          diagnostic: diag,
          durationMs: durationMs,
          countsAsSuccess: existingCount > 0,
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
          kind: existingCount > 0
              ? FacilitySyncFailureKind.cachedFallback
              : FacilitySyncFailureKind.parseEmpty,
          httpStatus: response.statusCode,
          finalUrl: finalUrl,
          contentType: contentType,
          blockedSummary: blockedCheck.summary,
          fingerprint: fingerprint,
          swimMentions: swimMentions,
          sessionsParsed: existingCount,
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
          fetchOutcome: existingCount > 0
              ? FacilityFetchOutcome.staleCached
              : FacilityFetchOutcome.parseEmpty,
          validationClass: FacilityValidationClass.failed,
          existingCount: existingCount,
          entries: entries,
          hash: hash,
          snapshotPath: snapshotPath,
          diagnostic: diag,
          durationMs: durationMs,
          countsAsSuccess: existingCount > 0,
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

      await _backoffTracker?.recordSuccess(facility.id);

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
    await _scheduleRepo.replaceSchedulesForFacility(
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
        scheduleTrustStatus: ScheduleTrustStatus.verified,
        scheduleSource: ScheduleSource.live,
        scheduleVerifiedAt: now,
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
        scheduleTrustStatus:
            f.scheduleTrustStatus == ScheduleTrustStatus.verified
                ? ScheduleTrustStatus.verified
                : f.scheduleTrustStatus,
      );
      return;
    }

    if (antiCorruption && result.commitCandidate != null) return;

    if (result.fetchOutcome == FacilityFetchOutcome.staleCached) {
      await _facilityRepo.updateSyncMetadata(
        facilityId: f.id,
        syncStatus: FacilitySyncStatus.stale,
        lastSuccessfulSyncAt: f.lastSuccessfulSyncAt,
        scheduleTrustStatus: _trustWhenBlocked(f),
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
        scheduleTrustStatus: result.existingCount > 0
            ? _trustWhenBlocked(f)
            : f.scheduleTrustStatus,
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
        scheduleTrustStatus: result.existingCount > 0
            ? _trustWhenBlocked(f)
            : f.scheduleTrustStatus,
      );
    }
  }

  ScheduleTrustStatus _trustWhenBlocked(Facility facility) {
    if (facility.scheduleTrustStatus == ScheduleTrustStatus.verified) {
      return ScheduleTrustStatus.cached;
    }
    if (facility.scheduleTrustStatus == ScheduleTrustStatus.fixture) {
      return ScheduleTrustStatus.fixture;
    }
    return facility.scheduleTrustStatus;
  }
}
