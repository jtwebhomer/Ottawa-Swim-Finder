import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';
import '../../core/utils/ottawa_time.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/scrape_log.dart';
import '../../domain/repositories/repositories.dart';
import '../services/ottawa_http_client.dart';
import '../services/schedule_sanity_checker.dart';
import '../services/schedule_trace_logger.dart';
import '../services/sync_safety_guard.dart';
import 'parsers/schedule_parser.dart';

class OttawaScraper {
  OttawaScraper({
    required FacilityRepository facilityRepo,
    required ScheduleRepository scheduleRepo,
    required ScrapeLogRepository scrapeLogRepo,
    OttawaHttpClient? httpClient,
    ScheduleTraceLogger? traceLogger,
    ScheduleSanityChecker? sanityChecker,
    SyncSafetyGuard? safetyGuard,
  })  : _facilityRepo = facilityRepo,
        _scheduleRepo = scheduleRepo,
        _scrapeLogRepo = scrapeLogRepo,
        _httpClient = httpClient ?? OttawaHttpClient(),
        _traceLogger = traceLogger ?? ScheduleTraceLogger(),
        _sanityChecker = sanityChecker ?? ScheduleSanityChecker(),
        _safetyGuard = safetyGuard ?? SyncSafetyGuard();

  final FacilityRepository _facilityRepo;
  final ScheduleRepository _scheduleRepo;
  final ScrapeLogRepository _scrapeLogRepo;
  final OttawaHttpClient _httpClient;
  final ScheduleTraceLogger _traceLogger;
  final ScheduleSanityChecker _sanityChecker;
  final SyncSafetyGuard _safetyGuard;
  late final ScheduleParser _parser = ScheduleParser(
    onDroppedTime: (facilityId, category, cell, reason) =>
        _traceLogger.logDroppedTimeCell(
      facilityId: facilityId,
      rawCategory: category,
      cellText: cell,
      reason: reason,
    ),
  );

  Future<void> seedFacilitiesIfEmpty() async {
    final existing = await _facilityRepo.getAllFacilities();
    if (existing.isNotEmpty) return;

    final jsonStr = await rootBundle.loadString('assets/facilities_seed.json');
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    final facilities = (data['facilities'] as List).cast<Map<String, dynamic>>();

    for (final f in facilities) {
      await _facilityRepo.upsertFacility(
        Facility(
          id: f['id'] as String,
          name: f['name'] as String,
          address: f['address'] as String?,
          latitude: (f['latitude'] as num?)?.toDouble(),
          longitude: (f['longitude'] as num?)?.toDouble(),
          region: f['region'] as String?,
          url:
              'https://ottawa.ca/en/recreation-and-parks/facilities/place-listing/${f['id']}',
        ),
      );
    }
  }

  Future<SyncResult> syncAll({bool force = false}) async {
    await seedFacilitiesIfEmpty();
    final facilities = await _facilityRepo.getAllFacilities();
    var updated = 0;
    var skipped = 0;
    var errors = 0;
    var rejected = 0;
    var http403Count = 0;
    final scheduleCountBefore = await _scheduleRepo.countAllSchedules();

    for (final facility in facilities) {
      final start = DateTime.now();
      final existingCount = await _scheduleRepo.countSchedulesForFacility(facility.id);

      try {
        final url = facility.url ??
            'https://ottawa.ca/en/recreation-and-parks/facilities/place-listing/${facility.id}';
        final response = await _httpClient.fetchFacilityPage(url);

        final html = response.body;
        final hash = sha256.convert(utf8.encode(html)).toString();

        if (!force && facility.contentHash == hash) {
          skipped++;
          await _scrapeLogRepo.insertLog(ScrapeLog(
            facilityId: facility.id,
            status: 'skipped',
            message: 'Content unchanged',
            contentHash: hash,
            durationMs: DateTime.now().difference(start).inMilliseconds,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));
          continue;
        }

        final snapshotPath = await _saveSnapshot(facility.id, html);
        _traceLogger.logParseStart(
          facilityId: facility.id,
          htmlLength: html.length,
          snapshotPath: snapshotPath,
        );

        final entries = _parser.parse(html, facility.id);
        final today = OttawaTime.todayDate();
        final swimMentions = ScheduleSanityChecker.countSwimMentions(html);

        _traceLogger.logParsedEntries(
          facilityId: facility.id,
          entries: entries,
          today: today,
        );

        final sanity = _sanityChecker.check(
          facilityId: facility.id,
          facilityName: facility.name,
          entries: entries,
          htmlSwimMentions: swimMentions,
        );

        final decision = _safetyGuard.evaluate(
          facilityId: facility.id,
          newEntries: entries,
          existingEntryCount: existingCount,
          htmlSwimMentions: swimMentions,
          httpStatus: response.statusCode,
        );

        if (!decision.allowWrite) {
          rejected++;
          await _scrapeLogRepo.insertLog(ScrapeLog(
            facilityId: facility.id,
            status: 'rejected',
            message: decision.reason,
            htmlSnapshotPath: snapshotPath,
            contentHash: hash,
            durationMs: DateTime.now().difference(start).inMilliseconds,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));
          continue;
        }

        await _scheduleRepo.deleteSchedulesForFacility(facility.id);
        await _scheduleRepo.upsertSchedules(facility.id, entries);

        final storedToday = entries.where((e) => e.date == today).length;
        _traceLogger.logStoredEntries(
          facilityId: facility.id,
          storedCount: entries.length,
          todayCount: storedToday,
        );

        await _facilityRepo.upsertFacility(
          facility.copyWith(
            contentHash: hash,
            lastUpdated: DateTime.now().millisecondsSinceEpoch,
          ),
        );

        updated++;
        final sanityNote =
            sanity.hasIssues ? ' sanityWarnings=${sanity.warnings.length}' : '';
        await _scrapeLogRepo.insertLog(ScrapeLog(
          facilityId: facility.id,
          status: 'success',
          message: '${entries.length} entries ($storedToday today)$sanityNote',
          htmlSnapshotPath: snapshotPath,
          contentHash: hash,
          durationMs: DateTime.now().difference(start).inMilliseconds,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
      } catch (e, st) {
        errors++;
        if (e is ScrapeHttpException && e.statusCode == 403) {
          http403Count++;
        }
        final message = e.toString();
        appLogger.e('Scrape failed for ${facility.id}', error: e, stackTrace: st);
        await _scrapeLogRepo.insertLog(ScrapeLog(
          facilityId: facility.id,
          status: 'error',
          message: '$message — kept $existingCount cached rows',
          durationMs: DateTime.now().difference(start).inMilliseconds,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }
    }

    final scheduleCountAfter = await _scheduleRepo.countAllSchedules();
    return SyncResult(
      updated: updated,
      skipped: skipped,
      errors: errors,
      rejected: rejected,
      http403Count: http403Count,
      scheduleCountBefore: scheduleCountBefore,
      scheduleCountAfter: scheduleCountAfter,
      totalFacilities: facilities.length,
    );
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
}

class ScrapeHttpException implements Exception {
  ScrapeHttpException({
    required this.statusCode,
    required this.url,
    this.bodySnippet,
  });

  final int statusCode;
  final String url;
  final String? bodySnippet;

  @override
  String toString() {
    final hint = statusCode == 403
        ? ' (ottawa.ca blocked request — retry with browser headers)'
        : '';
    final body = bodySnippet != null && bodySnippet!.isNotEmpty
        ? ' body="${bodySnippet!.replaceAll('\n', ' ').trim()}"'
        : '';
    return 'HTTP $statusCode for $url$hint$body';
  }
}

class SyncResult {
  const SyncResult({
    required this.updated,
    required this.skipped,
    required this.errors,
    this.rejected = 0,
    this.http403Count = 0,
    this.scheduleCountBefore = 0,
    this.scheduleCountAfter = 0,
    this.totalFacilities = 0,
  });

  final int updated;
  final int skipped;
  final int errors;
  final int rejected;
  final int http403Count;
  final int scheduleCountBefore;
  final int scheduleCountAfter;
  final int totalFacilities;

  bool get success => errors == 0;

  bool get isHealthy =>
      scheduleCountAfter > 0 ||
      (scheduleCountAfter >= scheduleCountBefore && errors < totalFacilities);

  String get statusLabel {
    if (errors == 0 && rejected == 0) return 'success';
    if (scheduleCountAfter > 0 && errors > 0) return 'partial';
    if (errors > 0) return 'failed';
    if (rejected > 0) return 'partial';
    return 'success';
  }
}
