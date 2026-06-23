import 'package:flutter_test/flutter_test.dart';
import 'package:ottawa_swim_finder/data/services/blocked_page_detector.dart';
import 'package:ottawa_swim_finder/data/services/sync_safety_guard.dart';
import 'package:ottawa_swim_finder/domain/entities/schedule_entry.dart';
import 'package:ottawa_swim_finder/domain/entities/sync_status.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ottawa_swim_finder/data/database/app_database.dart';
import 'package:ottawa_swim_finder/data/repositories/schedule_repository_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('RC1 chaos — bot-block classification', () {
    test('challenge page is blocked, not treated as valid schedule HTML', () {
      const html = '''
<html><head><title>Pardon Our Interruption</title></head>
<body>Please complete the security check.</body></html>
''';
      final result = BlockedPageDetector.check(html);
      expect(result.isBlocked, isTrue);

      final guard = SyncSafetyGuard();
      final decision = guard.evaluate(
        facilityId: 'jack-purcell-community-centre',
        newEntries: const [],
        existingEntryCount: 42,
        htmlSwimMentions: 0,
        httpStatus: 200,
      );
      expect(decision.allowWrite, isFalse);
    });

    test('empty parse with cached rows is rejected', () {
      final guard = SyncSafetyGuard();
      final decision = guard.evaluate(
        facilityId: 'plant-recreation-centre',
        newEntries: const [],
        existingEntryCount: 80,
        htmlSwimMentions: 0,
        httpStatus: 200,
      );
      expect(decision.allowWrite, isFalse);
    });

    test('blocked-only sync is partial success, not failed, when cache exists', () {
      final status = SyncStatus.fromCounts(
        totalFacilities: 20,
        updated: 0,
        skipped: 12,
        blocked: 8,
        parseEmpty: 0,
        parseRejected: 0,
        networkFailures: 0,
        pipelineCrashes: 0,
        antiCorruptionTriggered: false,
        scheduleCountAfter: 500,
      );
      expect(status, SyncStatus.partialSuccess);
      expect(status, isNot(SyncStatus.failed));
    });
  });

  group('RC1 chaos — sync health / timestamp gating', () {
    final guard = SyncSafetyGuard();

    test('blocked-only run with no updates is not healthy', () {
      expect(
        guard.isSyncHealthy(
          totalFacilities: 20,
          updated: 0,
          skipped: 20,
          errors: 0,
          scheduleCountBefore: 500,
          scheduleCountAfter: 500,
          blocked: 8,
        ),
        isFalse,
      );
    });

    test('successful partial update is healthy', () {
      expect(
        guard.isSyncHealthy(
          totalFacilities: 20,
          updated: 5,
          skipped: 15,
          errors: 0,
          scheduleCountBefore: 500,
          scheduleCountAfter: 510,
          blocked: 3,
        ),
        isTrue,
      );
    });

    test('anti-corruption global reject is not healthy', () {
      expect(
        guard.isSyncHealthy(
          totalFacilities: 20,
          updated: 0,
          skipped: 0,
          errors: 0,
          scheduleCountBefore: 500,
          scheduleCountAfter: 500,
          globalRejected: true,
        ),
        isFalse,
      );
    });

    test('network errors with preserved schedule count can be healthy', () {
      expect(
        guard.isSyncHealthy(
          totalFacilities: 20,
          updated: 0,
          skipped: 15,
          errors: 5,
          scheduleCountBefore: 500,
          scheduleCountAfter: 500,
        ),
        isTrue,
      );
    });
  });

  group('RC1 chaos — schedule persistence', () {
    test('replaceSchedulesForFacility preserves count and avoids duplicates', () async {
      final db = AppDatabase.instance;
      await db.close();

      final repo = ScheduleRepositoryImpl(db);
      const facilityId = 'rc1-test-pool';
      const entries = [
        ScheduleEntry(
          facilityId: facilityId,
          category: 'lane_swim',
          scheduleType: 'expanded',
          date: '2026-06-22',
          startTime: '08:00',
          endTime: '09:00',
        ),
        ScheduleEntry(
          facilityId: facilityId,
          category: 'public_swim',
          scheduleType: 'expanded',
          date: '2026-06-22',
          startTime: '17:00',
          endTime: '18:00',
        ),
      ];

      await repo.replaceSchedulesForFacility(facilityId, entries);
      expect(await repo.countSchedulesForFacility(facilityId), 2);

      await repo.replaceSchedulesForFacility(facilityId, entries);
      expect(await repo.countSchedulesForFacility(facilityId), 2);

      await repo.replaceSchedulesForFacility(facilityId, [entries.first]);
      expect(await repo.countSchedulesForFacility(facilityId), 1);
    });

    test('blocked write rejection leaves existing schedules intact', () async {
      final db = AppDatabase.instance;
      await db.close();

      final repo = ScheduleRepositoryImpl(db);
      const facilityId = 'rc1-guard-pool';
      const original = [
        ScheduleEntry(
          facilityId: facilityId,
          category: 'lane_swim',
          scheduleType: 'expanded',
          date: '2026-06-22',
          startTime: '08:00',
          endTime: '09:00',
        ),
      ];

      await repo.replaceSchedulesForFacility(facilityId, original);
      final guard = SyncSafetyGuard();
      final decision = guard.evaluate(
        facilityId: facilityId,
        newEntries: const [],
        existingEntryCount: 1,
        htmlSwimMentions: 0,
        httpStatus: 200,
      );
      expect(decision.allowWrite, isFalse);

      // Simulated scraper path: rejected write → no replace call.
      expect(await repo.countSchedulesForFacility(facilityId), 1);
    });
  });
}
