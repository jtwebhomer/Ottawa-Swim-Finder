/// Swim timing tier used for time-relevance scoring.
enum TimeRelevanceTier {
  activeNow,
  withinHour,
  today,
  tomorrow,
  weekend,
  none,
}

/// Decomposed facility score — each component computed independently.
class FacilityScoreBreakdown {
  const FacilityScoreBreakdown({
    required this.facilityId,
    required this.total,
    required this.baseImportance,
    required this.locationScore,
    required this.timeRelevanceScore,
    required this.behaviorScore,
    required this.recencyBoost,
    required this.contextBoost,
    required this.frictionPenalty,
    required this.habitBoost,
    required this.distanceKm,
    required this.timeTier,
  });

  final String facilityId;
  final double total;
  final double baseImportance;
  final double locationScore;
  final double timeRelevanceScore;
  final double behaviorScore;
  final double recencyBoost;
  final double contextBoost;
  final double frictionPenalty;
  final double habitBoost;
  final double distanceKm;
  final TimeRelevanceTier timeTier;
}
