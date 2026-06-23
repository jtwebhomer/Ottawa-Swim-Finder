/// Habit detection constants — fully local, no ML.
class HabitConstants {
  const HabitConstants._();

  static const int rollingWindowDays = 14;
  static const int coldStartEventThreshold = 10;
  static const double coldStartMultiplier = 0.3;
  static const int pruneEventsOlderThanDays = 45;
  static const double maxHabitBoost = 18;
  static const double pairBoostScale = 8;

  static const List<String> weekdayLabels = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
}

/// Morning / afternoon / evening buckets for habit patterns.
class HabitTimeBucket {
  const HabitTimeBucket._();

  static String forHour(int hour) {
    if (hour >= 5 && hour <= 11) return 'morning';
    if (hour >= 12 && hour <= 16) return 'afternoon';
    if (hour >= 17 && hour <= 22) return 'evening';
    return 'night';
  }
}
