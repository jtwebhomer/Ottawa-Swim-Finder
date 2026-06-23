import '../../core/utils/ottawa_time.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/repositories/repositories.dart';

/// Shared swim queries — Home, Map, and Facility sheets use identical logic.
class SwimQueryService {
  SwimQueryService(this._scheduleRepo);

  final ScheduleRepository _scheduleRepo;

  Future<FacilitySwimSummary> facilitySummary(String facilityId) async {
    final today = OttawaTime.todayDate();
    final tomorrow = OttawaTime.formatDate(
      DateTime.now().add(const Duration(days: 1)),
    );
    final now = OttawaTime.nowTime();

    final todaySwims = await _scheduleRepo.getTimelineForDate(
      today,
      facilityId: facilityId,
    );
    final tomorrowSwims = await _scheduleRepo.getTimelineForDate(
      tomorrow,
      facilityId: facilityId,
    );

    ScheduleEntry? current;
    ScheduleEntry? next;
    ScheduleEntry? tomorrowFirst;

    for (final s in todaySwims) {
      if (OttawaTime.isActiveAt(start: s.startTime, end: s.endTime, time: now)) {
        current ??= s;
      } else if (OttawaTime.isUpcomingAt(start: s.startTime, time: now)) {
        next ??= s;
      }
    }
    if (tomorrowSwims.isNotEmpty) {
      tomorrowFirst = tomorrowSwims.first;
    }

    return FacilitySwimSummary(
      facilityId: facilityId,
      current: current,
      next: next,
      tomorrowFirst: tomorrowFirst,
      todaySwims: todaySwims,
      tomorrowSwims: tomorrowSwims,
    );
  }

  Future<HomeSwimSections> homeSections({
    double? userLat,
    double? userLng,
  }) async {
    final today = OttawaTime.todayDate();
    final tomorrow = OttawaTime.formatDate(
      DateTime.now().add(const Duration(days: 1)),
    );
    final now = OttawaTime.nowTime();
    final nowMinutes = _toMinutes(now);

    final active = await _scheduleRepo.getActiveNow();
    final upcoming = await _scheduleRepo.getUpcomingSwims(
      fromDate: today,
      fromTime: now,
      limit: 200,
      userLat: userLat,
      userLng: userLng,
    );

    final startingSoon = upcoming.where((s) {
      if (s.date != today) return false;
      final startM = _toMinutes(s.startTime);
      return startM > nowMinutes && startM <= nowMinutes + 60;
    }).toList();

    final tonight = upcoming.where(
      (s) => s.date == today && s.startTime.compareTo('17:00') >= 0,
    ).toList();

    final tomorrowSwims = upcoming.where((s) => s.date == tomorrow).toList();

    return HomeSwimSections(
      swimmingNow: active,
      startingSoon: startingSoon,
      tonight: tonight,
      tomorrow: tomorrowSwims,
    );
  }

  int _toMinutes(String time) {
    final p = time.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }
}

class FacilitySwimSummary {
  const FacilitySwimSummary({
    required this.facilityId,
    this.current,
    this.next,
    this.tomorrowFirst,
    required this.todaySwims,
    required this.tomorrowSwims,
  });

  final String facilityId;
  final ScheduleEntry? current;
  final ScheduleEntry? next;
  final ScheduleEntry? tomorrowFirst;
  final List<ScheduleEntry> todaySwims;
  final List<ScheduleEntry> tomorrowSwims;

  bool get hasAnySwim =>
      current != null ||
      next != null ||
      tomorrowFirst != null ||
      todaySwims.isNotEmpty ||
      tomorrowSwims.isNotEmpty;
}

class HomeSwimSections {
  const HomeSwimSections({
    required this.swimmingNow,
    required this.startingSoon,
    required this.tonight,
    required this.tomorrow,
  });

  final List<ScheduleEntry> swimmingNow;
  final List<ScheduleEntry> startingSoon;
  final List<ScheduleEntry> tonight;
  final List<ScheduleEntry> tomorrow;

  bool get isEmpty =>
      swimmingNow.isEmpty &&
      startingSoon.isEmpty &&
      tonight.isEmpty &&
      tomorrow.isEmpty;
}

/// Reminder lead times in minutes.
class ReminderOptions {
  static const values = [15, 30, 60, 120, 1440];

  static String labelFor(int minutes) => switch (minutes) {
        15 => '15 minutes before',
        30 => '30 minutes before',
        60 => '1 hour before',
        120 => '2 hours before',
        1440 => '1 day before',
        _ => '$minutes minutes before',
      };
}
