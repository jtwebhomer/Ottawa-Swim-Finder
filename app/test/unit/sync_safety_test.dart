import 'package:flutter_test/flutter_test.dart';
import 'package:ottawa_swim_finder/core/constants/sync_thresholds.dart';
import 'package:ottawa_swim_finder/data/services/sync_safety_guard.dart';
import 'package:ottawa_swim_finder/domain/entities/schedule_entry.dart';

void main() {
  final guard = SyncSafetyGuard();

  test('rejects empty write when cached data exists', () {
    final decision = guard.evaluate(
      facilityId: 'jack-purcell-community-centre',
      newEntries: [],
      existingEntryCount: 42,
      htmlSwimMentions: 5,
      httpStatus: 200,
    );
    expect(decision.allowWrite, isFalse);
  });

  test('allows write when new entries are valid', () {
    final decision = guard.evaluate(
      facilityId: 'test',
      newEntries: const [
        ScheduleEntry(
          facilityId: 'test',
          category: 'public_swim',
          scheduleType: 'expanded',
          date: '2026-06-22',
          startTime: '18:00',
          endTime: '19:00',
        ),
      ],
      existingEntryCount: 0,
      htmlSwimMentions: 3,
      httpStatus: 200,
    );
    expect(decision.allowWrite, isTrue);
  });

  test('rejects HTTP error results', () {
    final decision = guard.evaluate(
      facilityId: 'test',
      newEntries: [],
      existingEntryCount: 10,
      htmlSwimMentions: 0,
      httpStatus: 403,
    );
    expect(decision.allowWrite, isFalse);
  });

  test('rejects facility session drop below threshold', () {
    final decision = guard.evaluate(
      facilityId: 'test',
      newEntries: List.generate(
        5,
        (i) => ScheduleEntry(
          facilityId: 'test',
          category: 'lane_swim',
          scheduleType: 'expanded',
          date: '2026-06-22',
          startTime: '18:00',
          endTime: '19:00',
        ),
      ),
      existingEntryCount: 100,
      htmlSwimMentions: 20,
      httpStatus: 200,
    );
    expect(decision.allowWrite, isFalse);
  });

  test('rejects global sync when session count collapses', () {
    final decision = guard.evaluateGlobalSync(
      countBefore: 1200,
      projectedCountAfter: 40,
      futureBefore: 900,
      projectedFutureAfter: 30,
      facilitiesParsed: 20,
      totalFacilities: 20,
    );
    expect(decision.allowWrite, isFalse);
    expect(decision.reason, contains('incomplete'));
  });

  test('allows global sync within ratio thresholds', () {
    final baseline = SyncThresholds.minBaselineSessionCount + 100;
    final projected =
        (baseline * SyncThresholds.minGlobalSessionRatio + 10).round();
    final decision = guard.evaluateGlobalSync(
      countBefore: baseline,
      projectedCountAfter: projected,
      futureBefore: 500,
      projectedFutureAfter: 200,
      facilitiesParsed: 20,
      totalFacilities: 20,
    );
    expect(decision.allowWrite, isTrue);
  });

  group('isSyncHealthy', () {
    test('rejects blocked-only runs with no facility updates', () {
      expect(
        guard.isSyncHealthy(
          totalFacilities: 10,
          updated: 0,
          skipped: 10,
          errors: 0,
          scheduleCountBefore: 200,
          scheduleCountAfter: 200,
          blocked: 10,
        ),
        isFalse,
      );
    });

    test('accepts runs with at least one facility updated', () {
      expect(
        guard.isSyncHealthy(
          totalFacilities: 10,
          updated: 2,
          skipped: 8,
          errors: 0,
          scheduleCountBefore: 200,
          scheduleCountAfter: 205,
          blocked: 3,
        ),
        isTrue,
      );
    });
  });
}
