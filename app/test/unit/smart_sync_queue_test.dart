import 'package:flutter_test/flutter_test.dart';
import 'package:ottawa_swim_finder/core/constants/sync_rate_limit_policy.dart';
import 'package:ottawa_swim_finder/data/services/facility_interaction_service.dart';
import 'package:ottawa_swim_finder/data/services/facility_priority_service.dart';
import 'package:ottawa_swim_finder/data/services/facility_ranking_service.dart';
import 'package:ottawa_swim_finder/data/services/habit_detection_service.dart';
import 'package:ottawa_swim_finder/data/services/smart_sync_queue.dart';
import 'package:ottawa_swim_finder/domain/entities/facility.dart';
import 'package:ottawa_swim_finder/domain/entities/facility_interaction.dart';
import 'package:ottawa_swim_finder/domain/entities/facility_priority.dart';
import 'package:ottawa_swim_finder/domain/entities/facility_type.dart';
import 'package:ottawa_swim_finder/domain/entities/habit_event.dart';
import 'package:ottawa_swim_finder/domain/entities/schedule_entry.dart';
import 'package:ottawa_swim_finder/domain/entities/sync_location_context.dart';
import 'package:ottawa_swim_finder/domain/entities/sync_status.dart';
import 'package:ottawa_swim_finder/domain/repositories/repositories.dart';

class _MemoryInteractionRepo implements FacilityInteractionRepository {
  final Map<String, FacilityInteractionMetrics> _data = {};

  @override
  Future<FacilityInteractionMetrics> getMetrics(String facilityId) async =>
      _data[facilityId] ?? FacilityInteractionMetrics(facilityId: facilityId);

  @override
  Future<Map<String, FacilityInteractionMetrics>> getAllMetrics() async =>
      Map.from(_data);

  @override
  Future<void> incrementView(String facilityId) async {
    final current = await getMetrics(facilityId);
    _data[facilityId] = FacilityInteractionMetrics(
      facilityId: facilityId,
      viewCount: current.viewCount + 1,
      lastViewedAt: DateTime.now().millisecondsSinceEpoch,
      savedCount: current.savedCount,
      swimDetailClicks: current.swimDetailClicks,
      impressionCount: current.impressionCount,
      ignoreCount: current.ignoreCount,
    );
  }

  @override
  Future<void> incrementSwimDetailClick(String facilityId) async {}

  @override
  Future<void> incrementSaved(String facilityId) async {}

  @override
  Future<void> decrementSaved(String facilityId) async {}

  @override
  Future<void> incrementImpression(String facilityId) async {}

  @override
  Future<void> incrementIgnore(String facilityId) async {}
}

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

class _MemoryScheduleRepo implements ScheduleRepository {
  final Map<String, List<ScheduleEntry>> _byFacility = {};

  void seed(String facilityId, {required String date, int count = 1}) {
    _byFacility.putIfAbsent(facilityId, () => []);
    for (var i = 0; i < count; i++) {
      _byFacility[facilityId]!.add(
        ScheduleEntry(
          facilityId: facilityId,
          date: date,
          startTime: '10:00',
          endTime: '11:00',
          category: 'Lane Swim',
          scheduleType: 'single',
        ),
      );
    }
  }

  @override
  Future<int> countSchedulesForFacility(String facilityId) async =>
      _byFacility[facilityId]?.length ?? 0;

  @override
  Future<int> countSchedulesForFacilityOnDate(String facilityId, String date) async =>
      _byFacility[facilityId]?.where((e) => e.date == date).length ?? 0;

  @override
  Future<List<ScheduleEntry>> getSchedulesForFacility(
    String facilityId, {
    String? date,
  }) async {
    final rows = _byFacility[facilityId] ?? [];
    if (date == null) return rows;
    return rows.where((e) => e.date == date).toList();
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Facility _facility({
  required String id,
  double? latitude,
  double? longitude,
  bool favorite = false,
  FacilitySyncStatus status = FacilitySyncStatus.ok,
  int? lastSuccessfulSyncAt,
}) {
  return Facility(
    id: id,
    name: id,
    latitude: latitude,
    longitude: longitude,
    lastSuccessfulSyncAt: lastSuccessfulSyncAt,
    syncStatus: status,
    isFavorite: favorite,
    facilityType: FacilityType.indoorPool,
  );
}

void main() {
  group('SmartSyncQueue adaptive scoring', () {
    late _MemoryScheduleRepo scheduleRepo;
    late SmartSyncQueue queue;
    final now = DateTime(2026, 6, 22, 12);
    const today = '2026-06-22';
    const anchor = SyncLocationContext(
      latitude: SyncLocationContext.fallbackLatitude,
      longitude: SyncLocationContext.fallbackLongitude,
      usesDeviceLocation: false,
    );

    setUp(() {
      scheduleRepo = _MemoryScheduleRepo();
      final interactions = FacilityInteractionService(_MemoryInteractionRepo());
      final habits = HabitDetectionService(_MemoryHabitRepo());
      final ranking = FacilityRankingService(
        scheduleRepo: scheduleRepo,
        interactionService: interactions,
        habitDetection: habits,
      );
      queue = SmartSyncQueue(FacilityPriorityService(ranking));
    });

    test('phase 1 caps at five facilities', () async {
      final old =
          now.subtract(const Duration(hours: 80)).millisecondsSinceEpoch;
      final facilities = List.generate(
        12,
        (i) => _facility(
          id: 'f$i',
          latitude: 45.42 + i * 0.001,
          longitude: -75.70,
          lastSuccessfulSyncAt: old,
        ),
      );

      final batch = await queue.planBatch(
        facilities: facilities,
        phase: SmartSyncPhase.immediate,
        anchor: anchor,
        force: false,
        staleThresholdHours: 48,
        now: now,
      );

      expect(batch.facilityIds.length, SyncRateLimitPolicy.phase1FacilityCount);
    });

    test('prioritizes favorites with adaptive score', () async {
      scheduleRepo.seed('fav', date: today);

      final old =
          now.subtract(const Duration(hours: 80)).millisecondsSinceEpoch;
      final facilities = [
        for (var i = 0; i < 6; i++)
          _facility(
            id: 'near$i',
            latitude: 45.421 + i * 0.0005,
            longitude: -75.701,
            lastSuccessfulSyncAt: old,
          ),
        _facility(
          id: 'fav',
          favorite: true,
          latitude: 45.48,
          longitude: -75.78,
          lastSuccessfulSyncAt: old,
        ),
      ];

      final batch = await queue.planBatch(
        facilities: facilities,
        phase: SmartSyncPhase.immediate,
        anchor: anchor,
        force: false,
        staleThresholdHours: 48,
        now: now,
      );

      expect(batch.facilityIds, contains('fav'));
      expect(batch.facilityIds.indexOf('fav'), lessThan(3));
    });

    test('skips fresh facilities during routine sync', () async {
      final freshAt =
          now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
      final facilities = [
        _facility(id: 'a', lastSuccessfulSyncAt: freshAt),
        _facility(id: 'b', lastSuccessfulSyncAt: freshAt),
      ];

      final batch = await queue.planBatch(
        facilities: facilities,
        phase: SmartSyncPhase.background,
        anchor: anchor,
        force: false,
        staleThresholdHours: 48,
        now: now,
      );

      expect(batch.facilityIds, isEmpty);
    });
  });
}
