import 'dart:math';

import '../../core/constants/habit_constants.dart';
import '../../domain/entities/habit_event.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/repositories/repositories.dart';

/// Detects recurring swim habits from weighted local event history.
class HabitDetectionService {
  HabitDetectionService(this._repo);

  final HabitEventRepository _repo;

  HabitStatistics _cachedStats = HabitStatistics.empty;
  int _cacheBuiltAtMs = 0;
  static const _cacheTtlMs = 60 * 1000;

  HabitStatistics get lastStatistics => _cachedStats;

  Future<void> recordAction({
    required String facilityId,
    required HabitActionType action,
    DateTime? at,
    String? swimStartTime,
    String? swimDate,
  }) async {
    final clock = at ?? DateTime.now();
    final hour =
        swimStartTime != null ? _hourFromTime(swimStartTime) : clock.hour;
    final day = swimDate != null ? _dayFromDate(swimDate) : clock.weekday;
    final bucket = HabitTimeBucket.forHour(hour);

    await _repo.insertEvent(
      HabitEvent(
        facilityId: facilityId,
        recordedAt: clock.millisecondsSinceEpoch,
        actionType: action,
        weight: action.weight,
        dayOfWeek: day,
        hourOfDay: hour,
        timeBucket: bucket,
        swimStartTime: swimStartTime,
      ),
    );

    final pruneBefore = clock
        .subtract(const Duration(days: HabitConstants.pruneEventsOlderThanDays))
        .millisecondsSinceEpoch;
    await _repo.pruneOlderThan(pruneBefore);
    _cacheBuiltAtMs = 0;
  }

  Future<HabitStatistics> loadStatistics({DateTime? now, bool forceRefresh = false}) async {
    final clock = now ?? DateTime.now();
    final nowMs = clock.millisecondsSinceEpoch;
    if (!forceRefresh &&
        nowMs - _cacheBuiltAtMs < _cacheTtlMs &&
        _cachedStats.eventCount > 0) {
      return _cachedStats;
    }

    final sinceMs = clock
        .subtract(const Duration(days: HabitConstants.rollingWindowDays))
        .millisecondsSinceEpoch;
    final events = await _repo.eventsSince(sinceMs);
    _cachedStats = _buildStatistics(events, clock);
    _cacheBuiltAtMs = nowMs;
    return _cachedStats;
  }

  HabitScoreResult scoreFor({
    required String facilityId,
    required int dayOfWeek,
    required int hourOfDay,
    required HabitStatistics stats,
  }) {
    if (stats.eventCount == 0 || stats.weightedEventTotal <= 0) {
      return const HabitScoreResult(
        habitBoost: 0,
        dayProbability: 0,
        hourProbability: 0,
        pairMatch: 0,
        coldStartDampening: HabitConstants.coldStartMultiplier,
      );
    }

    final dayProb = _probability(stats.dayOfWeekWeights, dayOfWeek);
    final hourProb = _probability(stats.hourOfDayWeights, hourOfDay);
    final bucket = HabitTimeBucket.forHour(hourOfDay);
    final pairKey = _pairKey(facilityId, dayOfWeek, bucket);
    final pairWeight = stats.facilityTimePairWeights[pairKey] ?? 0;
    final pairMatch = pairWeight / stats.weightedEventTotal;

    var boost = dayProb * hourProb * HabitConstants.maxHabitBoost;
    boost += pairMatch * HabitConstants.pairBoostScale;

    final dampening = stats.isColdStart
        ? HabitConstants.coldStartMultiplier
        : 1.0;
    boost *= dampening;

    return HabitScoreResult(
      habitBoost: boost,
      dayProbability: dayProb,
      hourProbability: hourProb,
      pairMatch: pairMatch,
      coldStartDampening: dampening,
    );
  }

  HabitScoreResult scoreForEntry({
    required ScheduleEntry entry,
    required HabitStatistics stats,
    required DateTime now,
  }) {
    final day = _dayOfWeekForEntry(entry, now);
    final hour = _hourFromTime(entry.startTime);
    return scoreFor(
      facilityId: entry.facilityId,
      dayOfWeek: day,
      hourOfDay: hour,
      stats: stats,
    );
  }

  String? hintForEntry({
    required ScheduleEntry entry,
    required HabitStatistics stats,
    required DateTime now,
  }) {
    if (stats.isColdStart || stats.eventCount < HabitConstants.coldStartEventThreshold) {
      return null;
    }

    final day = _dayOfWeekForEntry(entry, now);
    final hour = _hourFromTime(entry.startTime);
    final bucket = HabitTimeBucket.forHour(hour);
    final pairKey = _pairKey(entry.facilityId, day, bucket);
    final pairWeight = stats.facilityTimePairWeights[pairKey] ?? 0;

    if (pairWeight > 0 && pairWeight / stats.weightedEventTotal >= 0.08) {
      return 'You usually swim around this time';
    }

    final dayProb = _probability(stats.dayOfWeekWeights, day);
    if (dayProb >= 0.18) {
      final label = HabitConstants.weekdayLabels[day - 1];
      return 'Your typical $label swim is coming up';
    }

    final hourProb = _probability(stats.hourOfDayWeights, hour);
    if (hourProb >= 0.15) {
      return 'You usually swim around this time';
    }

    return null;
  }

  static String entryKey(ScheduleEntry entry) =>
      '${entry.facilityId}|${entry.date ?? ''}|${entry.startTime}';

  HabitStatistics _buildStatistics(List<HabitEvent> events, DateTime now) {
    if (events.isEmpty) {
      return HabitStatistics.empty;
    }

    final dayWeights = <int, double>{};
    final hourWeights = <int, double>{};
    final bucketWeights = <String, double>{};
    final pairWeights = <String, double>{};
    var weightedTotal = 0.0;

    for (final event in events) {
      final ageDays =
          now.difference(DateTime.fromMillisecondsSinceEpoch(event.recordedAt)).inHours /
              24.0;
      final decay = exp(-ageDays / HabitConstants.rollingWindowDays);
      final contribution = event.weight * decay;
      weightedTotal += contribution;

      dayWeights[event.dayOfWeek] =
          (dayWeights[event.dayOfWeek] ?? 0) + contribution;
      hourWeights[event.hourOfDay] =
          (hourWeights[event.hourOfDay] ?? 0) + contribution;
      bucketWeights[event.timeBucket] =
          (bucketWeights[event.timeBucket] ?? 0) + contribution;

      final pairKey = _pairKey(
        event.facilityId,
        event.dayOfWeek,
        event.timeBucket,
      );
      pairWeights[pairKey] = (pairWeights[pairKey] ?? 0) + contribution;
    }

    return HabitStatistics(
      dayOfWeekWeights: dayWeights,
      hourOfDayWeights: hourWeights,
      timeBucketWeights: bucketWeights,
      facilityTimePairWeights: pairWeights,
      eventCount: events.length,
      weightedEventTotal: weightedTotal,
      isColdStart: events.length < HabitConstants.coldStartEventThreshold,
    );
  }

  double _probability(Map<int, double> weights, int key) {
    if (weights.isEmpty) return 0;
    final total = weights.values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return 0;
    final smoothed = (weights[key] ?? 0) + 0.5;
    final smoothedTotal = total + 0.5 * weights.length;
    return smoothed / smoothedTotal;
  }

  String _pairKey(String facilityId, int dayOfWeek, String bucket) =>
      '$facilityId|$dayOfWeek|$bucket';

  int _hourFromTime(String time) {
    final parts = time.split(':');
    if (parts.isEmpty) return 12;
    return int.tryParse(parts[0]) ?? 12;
  }

  int _dayOfWeekForEntry(ScheduleEntry entry, DateTime now) {
    final date = entry.date;
    if (date != null && date.contains('-')) {
      return _dayFromDate(date);
    }
    return now.weekday;
  }

  int _dayFromDate(String date) {
    final p = date.split('-');
    if (p.length != 3) return DateTime.now().weekday;
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2])).weekday;
  }
}
