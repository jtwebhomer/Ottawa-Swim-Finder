/// Weighted user actions tracked for habit detection.
enum HabitActionType {
  view(0.2),
  click(0.5),
  save(1.0),
  directions(1.2);

  const HabitActionType(this.weight);
  final double weight;

  String get storageKey => name;
}

/// A single logged interaction used to infer swim habits.
class HabitEvent {
  const HabitEvent({
    this.id,
    required this.facilityId,
    required this.recordedAt,
    required this.actionType,
    required this.weight,
    required this.dayOfWeek,
    required this.hourOfDay,
    required this.timeBucket,
    this.swimStartTime,
  });

  final int? id;
  final String facilityId;
  final int recordedAt;
  final HabitActionType actionType;
  final double weight;
  final int dayOfWeek;
  final int hourOfDay;
  final String timeBucket;
  final String? swimStartTime;
}

/// Aggregated habit statistics over a rolling window.
class HabitStatistics {
  const HabitStatistics({
    required this.dayOfWeekWeights,
    required this.hourOfDayWeights,
    required this.timeBucketWeights,
    required this.facilityTimePairWeights,
    required this.eventCount,
    required this.weightedEventTotal,
    required this.isColdStart,
  });

  static const empty = HabitStatistics(
    dayOfWeekWeights: {},
    hourOfDayWeights: {},
    timeBucketWeights: {},
    facilityTimePairWeights: {},
    eventCount: 0,
    weightedEventTotal: 0,
    isColdStart: true,
  );

  final Map<int, double> dayOfWeekWeights;
  final Map<int, double> hourOfDayWeights;
  final Map<String, double> timeBucketWeights;
  final Map<String, double> facilityTimePairWeights;
  final int eventCount;
  final double weightedEventTotal;
  final bool isColdStart;
}

/// Result of habit scoring for one facility or swim entry.
class HabitScoreResult {
  const HabitScoreResult({
    required this.habitBoost,
    required this.dayProbability,
    required this.hourProbability,
    required this.pairMatch,
    required this.coldStartDampening,
  });

  final double habitBoost;
  final double dayProbability;
  final double hourProbability;
  final double pairMatch;
  final double coldStartDampening;
}
