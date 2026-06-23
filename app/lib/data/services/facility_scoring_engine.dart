import 'dart:math';

import '../../core/utils/geo_utils.dart';
import '../../core/utils/ottawa_time.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/facility_interaction.dart';
import '../../domain/entities/facility_score.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/entities/sync_location_context.dart';
import '../../domain/entities/sync_status.dart';

/// Inputs for a single facility score computation.
class FacilityScoringInput {
  const FacilityScoringInput({
    required this.facility,
    required this.distanceKm,
    required this.timeTier,
    required this.scheduleCount,
    required this.stalenessHours,
    required this.needsRefresh,
    required this.syncStatus,
    required this.now,
    this.interactions,
    this.habitBoost = 0,
  });

  final Facility facility;
  final double distanceKm;
  final TimeRelevanceTier timeTier;
  final int scheduleCount;
  final int stalenessHours;
  final bool needsRefresh;
  final FacilitySyncStatus syncStatus;
  final DateTime now;
  final FacilityInteractionMetrics? interactions;
  final double habitBoost;
}

/// Centralized adaptive scoring:
/// Score = Base + Location + Time + Behavior + Recency + Context - Friction
class FacilityScoringEngine {
  const FacilityScoringEngine();

  FacilityScoreBreakdown score(FacilityScoringInput input) {
    final baseImportance = _baseImportance(input.scheduleCount);
    final locationScore = _locationScore(input.distanceKm);
    final timeRelevanceScore = _timeRelevanceScore(input.timeTier);
    final behaviorScore = _behaviorScore(
      input.interactions,
      isFavorite: input.facility.isFavorite,
    );
    final recencyBoost = _recencyBoost(input.interactions, input.now);
    final contextBoost = _contextBoost(
      isFavorite: input.facility.isFavorite,
      timeTier: input.timeTier,
      needsRefresh: input.needsRefresh,
    );
    final frictionPenalty = _frictionPenalty(
      stalenessHours: input.stalenessHours,
      syncStatus: input.syncStatus,
      interactions: input.interactions,
    );

    final total = baseImportance +
        locationScore +
        timeRelevanceScore +
        behaviorScore +
        recencyBoost +
        contextBoost +
        input.habitBoost -
        frictionPenalty;

    return FacilityScoreBreakdown(
      facilityId: input.facility.id,
      total: max(0, total),
      baseImportance: baseImportance,
      locationScore: locationScore,
      timeRelevanceScore: timeRelevanceScore,
      behaviorScore: behaviorScore,
      recencyBoost: recencyBoost,
      contextBoost: contextBoost,
      frictionPenalty: frictionPenalty,
      habitBoost: input.habitBoost,
      distanceKm: input.distanceKm,
      timeTier: input.timeTier,
    );
  }

  double scoreSwimEntry({
    required FacilityScoreBreakdown facilityScore,
    required ScheduleEntry entry,
    required String today,
    required String tomorrow,
    required String nowTime,
    double entryHabitBoost = 0,
  }) {
    final entryTier = timeTierForEntry(
      entry: entry,
      today: today,
      tomorrow: tomorrow,
      nowTime: nowTime,
    );
    final entryTimeBoost = _timeRelevanceScore(entryTier);
    final facilityTimeBoost = facilityScore.timeRelevanceScore;
    // Use the stronger of facility-level or entry-level time signal once.
    final timeComponent =
        max(entryTimeBoost, facilityTimeBoost * 0.65) - facilityTimeBoost * 0.65 + entryTimeBoost;
    return facilityScore.total -
        facilityScore.timeRelevanceScore +
        timeComponent +
        entryHabitBoost;
  }

  TimeRelevanceTier timeTierForEntry({
    required ScheduleEntry entry,
    required String today,
    required String tomorrow,
    required String nowTime,
  }) {
    if (entry.date == today &&
        OttawaTime.isActiveAt(
          start: entry.startTime,
          end: entry.endTime,
          time: nowTime,
        )) {
      return TimeRelevanceTier.activeNow;
    }

    if (entry.date == today) {
      final nowM = _toMinutes(nowTime);
      final startM = _toMinutes(entry.startTime);
      if (startM > nowM && startM <= nowM + 60) {
        return TimeRelevanceTier.withinHour;
      }
      return TimeRelevanceTier.today;
    }

    if (entry.date == tomorrow) {
      return TimeRelevanceTier.tomorrow;
    }

    if (entry.date != null && _isWeekendDate(entry.date!)) {
      return TimeRelevanceTier.weekend;
    }

    return TimeRelevanceTier.none;
  }

  TimeRelevanceTier bestTierForEntries(
    Iterable<ScheduleEntry> entries, {
    required String today,
    required String tomorrow,
    required String nowTime,
  }) {
    var best = TimeRelevanceTier.none;
    for (final entry in entries) {
      final tier = timeTierForEntry(
        entry: entry,
        today: today,
        tomorrow: tomorrow,
        nowTime: nowTime,
      );
      if (_tierRank(tier) > _tierRank(best)) {
        best = tier;
      }
    }
    return best;
  }

  double distanceKm(Facility facility, SyncLocationContext anchor) {
    final lat = facility.latitude;
    final lng = facility.longitude;
    if (lat == null || lng == null) return 99;
    return GeoUtils.distanceKm(
      anchor.latitude,
      anchor.longitude,
      lat,
      lng,
    );
  }

  double _baseImportance(int scheduleCount) =>
      5 + min(scheduleCount / 12.0, 8);

  double _locationScore(double distanceKm) =>
      38 * exp(-distanceKm / 6.5);

  double _timeRelevanceScore(TimeRelevanceTier tier) => switch (tier) {
        TimeRelevanceTier.activeNow => 42,
        TimeRelevanceTier.withinHour => 32,
        TimeRelevanceTier.today => 16,
        TimeRelevanceTier.tomorrow => 8,
        TimeRelevanceTier.weekend => 4,
        TimeRelevanceTier.none => 0,
      };

  double _behaviorScore(
    FacilityInteractionMetrics? interactions, {
    required bool isFavorite,
  }) {
    final metrics = interactions;
    var score = 0.0;
    if (metrics != null) {
      score += min(metrics.viewCount * 2.5, 12);
      score += min(metrics.swimDetailClicks * 3.5, 14);
      score += min(metrics.savedCount * 4.0, 16);
    }
    if (isFavorite) score += 6;
    return min(score, 28);
  }

  double _recencyBoost(FacilityInteractionMetrics? interactions, DateTime now) {
    final lastViewed = interactions?.lastViewedAt;
    if (lastViewed == null) return 0;
    final hours =
        now.difference(DateTime.fromMillisecondsSinceEpoch(lastViewed)).inHours;
    if (hours <= 24) return 14;
    if (hours <= 72) return 8;
    if (hours <= 168) return 4;
    return 0;
  }

  double _contextBoost({
    required bool isFavorite,
    required TimeRelevanceTier timeTier,
    required bool needsRefresh,
  }) {
    var boost = 0.0;
    if (isFavorite) boost += 12;
    if (timeTier == TimeRelevanceTier.activeNow) boost += 10;
    if (needsRefresh) boost += 4;
    return boost;
  }

  double _frictionPenalty({
    required int stalenessHours,
    required FacilitySyncStatus syncStatus,
    FacilityInteractionMetrics? interactions,
  }) {
    var penalty = 0.0;
    if (stalenessHours > 24) {
      penalty += min((stalenessHours - 24) / 12.0, 12);
    }
    if (syncStatus == FacilitySyncStatus.stale) penalty += 6;
    if (syncStatus == FacilitySyncStatus.failed) penalty += 4;

    final metrics = interactions;
    if (metrics != null) {
      penalty += min(metrics.ignoreCount * 2.5, 10);
      penalty += min(metrics.passiveIgnoreSignal * 1.5, 8);
    }
    return penalty;
  }

  int _tierRank(TimeRelevanceTier tier) => switch (tier) {
        TimeRelevanceTier.activeNow => 5,
        TimeRelevanceTier.withinHour => 4,
        TimeRelevanceTier.today => 3,
        TimeRelevanceTier.tomorrow => 2,
        TimeRelevanceTier.weekend => 1,
        TimeRelevanceTier.none => 0,
      };

  int _toMinutes(String time) {
    final p = time.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  bool _isWeekendDate(String date) {
    final parts = date.split('-');
    if (parts.length != 3) return false;
    final dt = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    return dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday;
  }
}
