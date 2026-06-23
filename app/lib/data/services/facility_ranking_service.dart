import 'dart:math';

import '../../core/utils/ottawa_time.dart';
import '../../domain/entities/habit_event.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/facility_interaction.dart';
import '../../domain/entities/facility_priority.dart';
import '../../domain/entities/facility_score.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/entities/sync_location_context.dart';
import '../../domain/entities/sync_status.dart';
import '../../domain/repositories/repositories.dart';
import 'facility_interaction_service.dart';
import 'facility_scoring_engine.dart';
import 'habit_detection_service.dart';
import 'swim_query_service.dart';

/// Shared ranking context for UI and smart sync.
class FacilityRankingContext {
  const FacilityRankingContext({
    required this.anchor,
    required this.today,
    required this.tomorrow,
    required this.nowTime,
    required this.staleThresholdHours,
    required this.interactionsByFacility,
    required this.scheduleCountByFacility,
    required this.timeTierByFacility,
    required this.habitStatistics,
    required this.now,
  });

  final SyncLocationContext anchor;
  final String today;
  final String tomorrow;
  final String nowTime;
  final int staleThresholdHours;
  final Map<String, FacilityInteractionMetrics> interactionsByFacility;
  final Map<String, int> scheduleCountByFacility;
  final Map<String, TimeRelevanceTier> timeTierByFacility;
  final HabitStatistics habitStatistics;
  final DateTime now;
}

/// Unified adaptive ranking for Home UI and smart sync prioritization.
class FacilityRankingService {
  FacilityRankingService({
    required ScheduleRepository scheduleRepo,
    required FacilityInteractionService interactionService,
    required HabitDetectionService habitDetection,
    FacilityScoringEngine? scoringEngine,
  })  : _scheduleRepo = scheduleRepo,
        _interactions = interactionService,
        _habits = habitDetection,
        _engine = scoringEngine ?? const FacilityScoringEngine();

  final ScheduleRepository _scheduleRepo;
  final FacilityInteractionService _interactions;
  final HabitDetectionService _habits;
  final FacilityScoringEngine _engine;

  List<FacilityScoreBreakdown> lastBreakdowns = [];
  List<FacilityPriorityScore> lastRankings = [];
  Map<String, String> lastHabitHints = {};

  Future<FacilityRankingContext> buildContext({
    required List<Facility> facilities,
    required SyncLocationContext anchor,
    required int staleThresholdHours,
    DateTime? now,
  }) async {
    final clock = now ?? DateTime.now();
    final today = OttawaTime.formatDate(clock);
    final tomorrow = OttawaTime.formatDate(clock.add(const Duration(days: 1)));
    final nowTime = OttawaTime.formatTime(clock);

    final allInteractions = await _interactions.getAllMetrics();
    final habitStatistics = await _habits.loadStatistics(now: clock);

    final scheduleCountByFacility = <String, int>{};
    final timeTierByFacility = <String, TimeRelevanceTier>{};

    for (final facility in facilities) {
      scheduleCountByFacility[facility.id] =
          await _scheduleRepo.countSchedulesForFacility(facility.id);

      final todaySwims = await _scheduleRepo.getSchedulesForFacility(
        facility.id,
        date: today,
      );
      final tomorrowSwims = await _scheduleRepo.getSchedulesForFacility(
        facility.id,
        date: tomorrow,
      );
      timeTierByFacility[facility.id] = _engine.bestTierForEntries(
        [...todaySwims, ...tomorrowSwims],
        today: today,
        tomorrow: tomorrow,
        nowTime: nowTime,
      );
    }

    // Ensure recently viewed ids exist even if metrics row was just created.
    final recentIds = await _interactions.recentFacilityIds();
    for (final id in recentIds) {
      allInteractions.putIfAbsent(
        id,
        () => FacilityInteractionMetrics(facilityId: id),
      );
    }

    return FacilityRankingContext(
      anchor: anchor,
      today: today,
      tomorrow: tomorrow,
      nowTime: nowTime,
      staleThresholdHours: staleThresholdHours,
      interactionsByFacility: allInteractions,
      scheduleCountByFacility: scheduleCountByFacility,
      timeTierByFacility: timeTierByFacility,
      habitStatistics: habitStatistics,
      now: clock,
    );
  }

  int _hourNow(String nowTime) {
    final parts = nowTime.split(':');
    return int.tryParse(parts.first) ?? 12;
  }

  List<FacilityScoreBreakdown> scoreFacilities({
    required List<Facility> facilities,
    required FacilityRankingContext context,
    Set<String> backoffFacilityIds = const {},
  }) {
    final breakdowns = facilities.map((facility) {
      final stalenessHours = _stalenessHours(facility, context.now);
      final habit = _habits.scoreFor(
        facilityId: facility.id,
        dayOfWeek: context.now.weekday,
        hourOfDay: _hourNow(context.nowTime),
        stats: context.habitStatistics,
      );
      return _engine.score(
        FacilityScoringInput(
          facility: facility,
          distanceKm: _engine.distanceKm(facility, context.anchor),
          timeTier: context.timeTierByFacility[facility.id] ??
              TimeRelevanceTier.none,
          scheduleCount: context.scheduleCountByFacility[facility.id] ?? 0,
          stalenessHours: stalenessHours,
          needsRefresh: _needsRefresh(
            facility: facility,
            staleThresholdHours: context.staleThresholdHours,
            now: context.now,
            backoff: backoffFacilityIds.contains(facility.id),
          ),
          syncStatus: facility.syncStatus,
          now: context.now,
          interactions: context.interactionsByFacility[facility.id],
          habitBoost: habit.habitBoost,
        ),
      );
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    lastBreakdowns = breakdowns;
    lastRankings = breakdowns
        .map(
          (b) => FacilityPriorityScore(
            facilityId: b.facilityId,
            score: b.total,
            distanceKm: b.distanceKm,
            hasSwimsToday: b.timeTier == TimeRelevanceTier.activeNow ||
                b.timeTier == TimeRelevanceTier.withinHour ||
                b.timeTier == TimeRelevanceTier.today,
            isFavorite: facilities
                .firstWhere((f) => f.id == b.facilityId)
                .isFavorite,
            isRecentlyViewed: _isRecentlyViewed(
              context.interactionsByFacility[b.facilityId],
              context.now,
            ),
            needsRefresh: _needsRefresh(
              facility: facilities.firstWhere((f) => f.id == b.facilityId),
              staleThresholdHours: context.staleThresholdHours,
              now: context.now,
              backoff: backoffFacilityIds.contains(b.facilityId),
            ),
            scheduleCount:
                context.scheduleCountByFacility[b.facilityId] ?? 0,
            stalenessHours: _stalenessHours(
              facilities.firstWhere((f) => f.id == b.facilityId),
              context.now,
            ),
            breakdown: b,
          ),
        )
        .toList();

    return breakdowns;
  }

  Future<HomeSwimSections> sortHomeSections(
    HomeSwimSections sections, {
    required List<Facility> facilities,
    SyncLocationContext? anchor,
  }) async {
    if (facilities.isEmpty) return sections;

    final locationAnchor = anchor ?? SyncLocationContext.fallback();
    final context = await buildContext(
      facilities: facilities,
      anchor: locationAnchor,
      staleThresholdHours: 48,
    );
    final breakdownById = {
      for (final b in scoreFacilities(
        facilities: facilities,
        context: context,
      ))
        b.facilityId: b,
    };

    final habitHints = <String, String>{};

    double entryScore(ScheduleEntry entry) {
      final facilityScore = breakdownById[entry.facilityId];
      if (facilityScore == null) return 0;
      final entryHabit = _habits.scoreForEntry(
        entry: entry,
        stats: context.habitStatistics,
        now: context.now,
      );
      final hint = _habits.hintForEntry(
        entry: entry,
        stats: context.habitStatistics,
        now: context.now,
      );
      if (hint != null) {
        habitHints[HabitDetectionService.entryKey(entry)] = hint;
      }
      return _engine.scoreSwimEntry(
        facilityScore: facilityScore,
        entry: entry,
        today: context.today,
        tomorrow: context.tomorrow,
        nowTime: context.nowTime,
        entryHabitBoost: entryHabit.habitBoost,
      );
    }

    List<ScheduleEntry> sortList(List<ScheduleEntry> entries) {
      final copy = [...entries];
      copy.sort((a, b) {
        final scoreCmp = entryScore(b).compareTo(entryScore(a));
        if (scoreCmp != 0) return scoreCmp;
        final dateCmp = (a.date ?? '').compareTo(b.date ?? '');
        if (dateCmp != 0) return dateCmp;
        return a.startTime.compareTo(b.startTime);
      });
      return copy;
    }

    lastHabitHints = habitHints;

    return HomeSwimSections(
      swimmingNow: sortList(sections.swimmingNow),
      startingSoon: sortList(sections.startingSoon),
      tonight: sortList(sections.tonight),
      tomorrow: sortList(sections.tomorrow),
      habitHints: habitHints,
    );
  }

  double scoreForFacilityId(String facilityId) {
    for (final b in lastBreakdowns) {
      if (b.facilityId == facilityId) return b.total;
    }
    return 0;
  }

  bool _isRecentlyViewed(FacilityInteractionMetrics? metrics, DateTime now) {
    final last = metrics?.lastViewedAt;
    if (last == null) return false;
    return now.difference(DateTime.fromMillisecondsSinceEpoch(last)).inHours <= 72;
  }

  bool _needsRefresh({
    required Facility facility,
    required int staleThresholdHours,
    required DateTime now,
    required bool backoff,
  }) {
    if (backoff) return false;
    if (facility.syncStatus == FacilitySyncStatus.failed) return true;
    if (facility.syncStatus == FacilitySyncStatus.stale) return true;
    final lastOk = facility.lastSuccessfulSyncAt;
    if (lastOk == null) return true;
    final staleBefore =
        now.subtract(Duration(hours: staleThresholdHours)).millisecondsSinceEpoch;
    return lastOk < staleBefore;
  }

  int _stalenessHours(Facility facility, DateTime now) {
    final lastOk = facility.lastSuccessfulSyncAt;
    if (lastOk == null) return 999;
    return max(
      0,
      now.difference(DateTime.fromMillisecondsSinceEpoch(lastOk)).inHours,
    );
  }
}
