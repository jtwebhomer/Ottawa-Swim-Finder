import '../entities/facility_score.dart';

/// Staged smart sync execution tiers.
enum SmartSyncPhase {
  /// Top 3–5 highest-value facilities for immediate Home usefulness.
  immediate,

  /// Expand nearby / high-priority coverage.
  expansion,

  /// Low-priority and stale facilities during idle background refresh.
  background,
}

/// Computed ranking inputs for one facility.
class FacilityPriorityScore {
  const FacilityPriorityScore({
    required this.facilityId,
    required this.score,
    required this.distanceKm,
    required this.hasSwimsToday,
    required this.isFavorite,
    required this.isRecentlyViewed,
    required this.needsRefresh,
    required this.scheduleCount,
    required this.stalenessHours,
    this.breakdown,
  });

  final String facilityId;
  final double score;
  final double distanceKm;
  final bool hasSwimsToday;
  final bool isFavorite;
  final bool isRecentlyViewed;
  final bool needsRefresh;
  final int scheduleCount;
  final int stalenessHours;
  final FacilityScoreBreakdown? breakdown;
}

/// Batch selected for a single smart-sync phase.
class SmartSyncBatch {
  const SmartSyncBatch({
    required this.phase,
    required this.facilityIds,
    required this.rankings,
  });

  final SmartSyncPhase phase;
  final List<String> facilityIds;
  final List<FacilityPriorityScore> rankings;
}
