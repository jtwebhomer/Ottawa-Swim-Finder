import 'package:flutter_test/flutter_test.dart';
import 'package:ottawa_swim_finder/core/constants/habit_constants.dart';
import 'package:ottawa_swim_finder/data/services/habit_detection_service.dart';
import 'package:ottawa_swim_finder/domain/entities/habit_event.dart';
import 'package:ottawa_swim_finder/domain/entities/schedule_entry.dart';
import 'package:ottawa_swim_finder/domain/repositories/repositories.dart';

class _MemoryHabitRepo implements HabitEventRepository {
  final List<HabitEvent> _events = [];

  @override
  Future<void> insertEvent(HabitEvent event) async {
    _events.add(event);
  }

  @override
  Future<List<HabitEvent>> eventsSince(int sinceMs) async =>
      _events.where((e) => e.recordedAt >= sinceMs).toList();

  @override
  Future<int> countEventsSince(int sinceMs) async =>
      _events.where((e) => e.recordedAt >= sinceMs).length;

  @override
  Future<void> pruneOlderThan(int beforeMs) async {
    _events.removeWhere((e) => e.recordedAt < beforeMs);
  }
}

void main() {
  group('HabitDetectionService', () {
    late HabitDetectionService service;
    final now = DateTime(2026, 6, 24, 18, 30); // Wednesday evening

    setUp(() {
      service = HabitDetectionService(_MemoryHabitRepo());
    });

    Future<void> seedWednesdayEveningHabit() async {
      for (var i = 0; i < 12; i++) {
        final at = now.subtract(Duration(days: i));
        await service.recordAction(
          facilityId: 'plant-recreation-centre',
          action: HabitActionType.click,
          at: at,
          swimStartTime: '18:00',
          swimDate: '2026-06-24',
        );
      }
    }

    test('records weighted events with day and bucket metadata', () async {
      await service.recordAction(
        facilityId: 'pool-a',
        action: HabitActionType.directions,
        at: now,
        swimStartTime: '18:00',
      );

      final stats = await service.loadStatistics(now: now, forceRefresh: true);
      expect(stats.eventCount, 1);
      expect(stats.dayOfWeekWeights[DateTime.wednesday], greaterThan(0));
      expect(stats.timeBucketWeights['evening'], greaterThan(0));
    });

    test('cold start dampens habit boost below threshold', () async {
      for (var i = 0; i < 5; i++) {
        await service.recordAction(
          facilityId: 'pool-a',
          action: HabitActionType.save,
          at: now.subtract(Duration(days: i)),
          swimStartTime: '18:00',
        );
      }

      final stats = await service.loadStatistics(now: now, forceRefresh: true);
      expect(stats.isColdStart, isTrue);

      final score = service.scoreFor(
        facilityId: 'pool-a',
        dayOfWeek: DateTime.wednesday,
        hourOfDay: 18,
        stats: stats,
      );
      expect(score.coldStartDampening, HabitConstants.coldStartMultiplier);
    });

    test('learned Wednesday evening pattern boosts matching entries', () async {
      await seedWednesdayEveningHabit();
      final stats = await service.loadStatistics(now: now, forceRefresh: true);
      expect(stats.isColdStart, isFalse);

      final matching = service.scoreForEntry(
        entry: const ScheduleEntry(
          facilityId: 'plant-recreation-centre',
          date: '2026-06-24',
          startTime: '18:15',
          endTime: '19:15',
          category: 'Lane Swim',
          scheduleType: 'single',
        ),
        stats: stats,
        now: now,
      );
      final otherDay = service.scoreForEntry(
        entry: const ScheduleEntry(
          facilityId: 'plant-recreation-centre',
          date: '2026-06-26',
          startTime: '18:15',
          endTime: '19:15',
          category: 'Lane Swim',
          scheduleType: 'single',
        ),
        stats: stats,
        now: now,
      );

      expect(matching.habitBoost, greaterThan(otherDay.habitBoost));
    });

    test('generates subtle personalization hints after enough data', () async {
      await seedWednesdayEveningHabit();
      final stats = await service.loadStatistics(now: now, forceRefresh: true);

      final hint = service.hintForEntry(
        entry: const ScheduleEntry(
          facilityId: 'plant-recreation-centre',
          date: '2026-06-24',
          startTime: '18:15',
          endTime: '19:15',
          category: 'Lane Swim',
          scheduleType: 'single',
        ),
        stats: stats,
        now: now,
      );

      expect(hint, isNotNull);
      expect(
        hint,
        anyOf(
          contains('Wednesday'),
          contains('usually swim around this time'),
        ),
      );
    });
  });
}
