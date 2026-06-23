import 'package:flutter_test/flutter_test.dart';
import 'package:ottawa_swim_finder/data/services/facility_scoring_engine.dart';
import 'package:ottawa_swim_finder/domain/entities/facility.dart';
import 'package:ottawa_swim_finder/domain/entities/facility_interaction.dart';
import 'package:ottawa_swim_finder/domain/entities/facility_score.dart';
import 'package:ottawa_swim_finder/domain/entities/facility_type.dart';
import 'package:ottawa_swim_finder/domain/entities/schedule_entry.dart';
import 'package:ottawa_swim_finder/domain/entities/sync_location_context.dart';
import 'package:ottawa_swim_finder/domain/entities/sync_status.dart';

Facility _facility({
  required String id,
  double? latitude,
  double? longitude,
  bool favorite = false,
}) {
  return Facility(
    id: id,
    name: id,
    latitude: latitude,
    longitude: longitude,
    isFavorite: favorite,
    facilityType: FacilityType.indoorPool,
  );
}

void main() {
  const engine = FacilityScoringEngine();
  final now = DateTime(2026, 6, 22, 14);

  group('FacilityScoringEngine', () {
    test('computes independent score components', () {
      final breakdown = engine.score(
        FacilityScoringInput(
          facility: _facility(id: 'near', latitude: 45.42, longitude: -75.70),
          distanceKm: 1.2,
          timeTier: TimeRelevanceTier.activeNow,
          scheduleCount: 24,
          stalenessHours: 10,
          needsRefresh: false,
          syncStatus: FacilitySyncStatus.ok,
          now: now,
          interactions: const FacilityInteractionMetrics(
            facilityId: 'near',
            viewCount: 4,
            swimDetailClicks: 2,
            savedCount: 1,
            lastViewedAt: null,
          ),
        ),
      );

      expect(breakdown.baseImportance, greaterThan(0));
      expect(breakdown.locationScore, greaterThan(0));
      expect(breakdown.timeRelevanceScore, 42);
      expect(breakdown.behaviorScore, greaterThan(0));
      expect(breakdown.total, greaterThan(breakdown.locationScore));
    });

    test('ranks nearer active swims above distant pools', () {
      final near = engine.score(
        FacilityScoringInput(
          facility: _facility(id: 'near', latitude: 45.42, longitude: -75.70),
          distanceKm: 1,
          timeTier: TimeRelevanceTier.activeNow,
          scheduleCount: 10,
          stalenessHours: 12,
          needsRefresh: false,
          syncStatus: FacilitySyncStatus.ok,
          now: now,
        ),
      );
      final far = engine.score(
        FacilityScoringInput(
          facility: _facility(id: 'far', latitude: 45.50, longitude: -75.85),
          distanceKm: 12,
          timeTier: TimeRelevanceTier.today,
          scheduleCount: 10,
          stalenessHours: 12,
          needsRefresh: false,
          syncStatus: FacilitySyncStatus.ok,
          now: now,
        ),
      );

      expect(near.total, greaterThan(far.total));
    });

    test('behavior and recency boost personalized facilities', () {
      final viewedAt = now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch;
      final personalized = engine.score(
        FacilityScoringInput(
          facility: _facility(id: 'fav', favorite: true),
          distanceKm: 8,
          timeTier: TimeRelevanceTier.withinHour,
          scheduleCount: 8,
          stalenessHours: 20,
          needsRefresh: false,
          syncStatus: FacilitySyncStatus.ok,
          now: now,
          interactions: FacilityInteractionMetrics(
            facilityId: 'fav',
            viewCount: 6,
            swimDetailClicks: 4,
            savedCount: 2,
            lastViewedAt: viewedAt,
          ),
        ),
      );
      final cold = engine.score(
        FacilityScoringInput(
          facility: _facility(id: 'cold'),
          distanceKm: 8,
          timeTier: TimeRelevanceTier.withinHour,
          scheduleCount: 8,
          stalenessHours: 20,
          needsRefresh: false,
          syncStatus: FacilitySyncStatus.ok,
          now: now,
        ),
      );

      expect(personalized.behaviorScore, greaterThan(cold.behaviorScore));
      expect(personalized.recencyBoost, greaterThan(0));
      expect(personalized.total, greaterThan(cold.total));
    });

    test('applies staleness friction penalty', () {
      final fresh = engine.score(
        FacilityScoringInput(
          facility: _facility(id: 'fresh'),
          distanceKm: 3,
          timeTier: TimeRelevanceTier.today,
          scheduleCount: 12,
          stalenessHours: 8,
          needsRefresh: false,
          syncStatus: FacilitySyncStatus.ok,
          now: now,
        ),
      );
      final stale = engine.score(
        FacilityScoringInput(
          facility: _facility(id: 'stale'),
          distanceKm: 3,
          timeTier: TimeRelevanceTier.today,
          scheduleCount: 12,
          stalenessHours: 96,
          needsRefresh: true,
          syncStatus: FacilitySyncStatus.stale,
          now: now,
        ),
      );

      expect(stale.frictionPenalty, greaterThan(fresh.frictionPenalty));
      expect(fresh.total, greaterThan(stale.total));
    });

    test('entry score prioritizes active now swims', () {
      const facilityScore = FacilityScoreBreakdown(
        facilityId: 'pool',
        total: 80,
        baseImportance: 8,
        locationScore: 30,
        timeRelevanceScore: 16,
        behaviorScore: 10,
        recencyBoost: 4,
        contextBoost: 12,
        frictionPenalty: 0,
        habitBoost: 0,
        distanceKm: 2,
        timeTier: TimeRelevanceTier.today,
      );

      final activeEntry = ScheduleEntry(
        facilityId: 'pool',
        date: '2026-06-22',
        startTime: '13:30',
        endTime: '15:00',
        category: 'Lane Swim',
        scheduleType: 'single',
      );
      final laterEntry = ScheduleEntry(
        facilityId: 'pool',
        date: '2026-06-22',
        startTime: '19:00',
        endTime: '20:00',
        category: 'Lane Swim',
        scheduleType: 'single',
      );

      final activeScore = engine.scoreSwimEntry(
        facilityScore: facilityScore,
        entry: activeEntry,
        today: '2026-06-22',
        tomorrow: '2026-06-23',
        nowTime: '14:00',
      );
      final laterScore = engine.scoreSwimEntry(
        facilityScore: facilityScore,
        entry: laterEntry,
        today: '2026-06-22',
        tomorrow: '2026-06-23',
        nowTime: '14:00',
      );

      expect(activeScore, greaterThan(laterScore));
    });

    test('location score uses exponential decay from anchor', () {
      final near = engine.distanceKm(
        _facility(id: 'a', latitude: 45.4236, longitude: -75.7009),
        SyncLocationContext.fallback(),
      );
      final far = engine.distanceKm(
        _facility(id: 'b', latitude: 45.50, longitude: -75.85),
        SyncLocationContext.fallback(),
      );

      expect(near, lessThan(1));
      expect(far, greaterThan(8));
    });
  });
}
