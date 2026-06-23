import '../../core/constants/app_constants.dart';
import '../../core/utils/ottawa_time.dart';
import '../../domain/entities/schedule_entry.dart';

enum SwimSessionStatus {
  active,
  upcoming,
  ended,
}

class SwimSessionStatusInfo {
  const SwimSessionStatusInfo({
    required this.status,
    required this.label,
  });

  final SwimSessionStatus status;
  final String label;
}

/// Presentation helpers for schedule cards and facility views.
class SwimSessionPresenter {
  static String formatTime12h(String time24) {
    final parts = time24.split(':');
    if (parts.length != 2) return time24;
    var hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final period = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    final minuteStr = minute.toString().padLeft(2, '0');
    return '$hour:$minuteStr $period';
  }

  static String formatRange(ScheduleEntry entry) =>
      '${formatTime12h(entry.startTime)} – ${formatTime12h(entry.endTime)}';

  static SwimSessionStatusInfo statusFor(ScheduleEntry entry, {String? nowTime}) {
    final now = nowTime ?? OttawaTime.nowTime();
    if (OttawaTime.isActiveAt(
      start: entry.startTime,
      end: entry.endTime,
      time: now,
    )) {
      return const SwimSessionStatusInfo(
        status: SwimSessionStatus.active,
        label: 'Currently swimming',
      );
    }
    if (OttawaTime.isUpcomingAt(start: entry.startTime, time: now)) {
      final mins = _minutesUntil(entry.startTime, now);
      if (mins <= 60) {
        return SwimSessionStatusInfo(
          status: SwimSessionStatus.upcoming,
          label: 'Starts in $mins minute${mins == 1 ? '' : 's'}',
        );
      }
      return const SwimSessionStatusInfo(
        status: SwimSessionStatus.upcoming,
        label: 'Upcoming today',
      );
    }
    return const SwimSessionStatusInfo(
      status: SwimSessionStatus.ended,
      label: 'Ended',
    );
  }

  static int _minutesUntil(String startTime, String nowTime) {
    final start = _toMinutes(startTime);
    final now = _toMinutes(nowTime);
    return (start - now).clamp(0, 24 * 60);
  }

  static int _toMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  static List<ScheduleEntry> sorted(List<ScheduleEntry> entries) {
    final copy = List<ScheduleEntry>.from(entries);
    copy.sort((a, b) => a.startTime.compareTo(b.startTime));
    return copy;
  }

  static ScheduleEntry? nextUpcoming(
    List<ScheduleEntry> entries, {
    String? nowTime,
  }) {
    final now = nowTime ?? OttawaTime.nowTime();
    final upcoming = sorted(entries)
        .where((e) => OttawaTime.isUpcomingAt(start: e.startTime, time: now))
        .toList();
    return upcoming.isEmpty ? null : upcoming.first;
  }

  static ScheduleEntry? activeNow(
    List<ScheduleEntry> entries, {
    String? nowTime,
  }) {
    final now = nowTime ?? OttawaTime.nowTime();
    for (final entry in sorted(entries)) {
      if (OttawaTime.isActiveAt(
        start: entry.startTime,
        end: entry.endTime,
        time: now,
      )) {
        return entry;
      }
    }
    return null;
  }

  static String typeLabel(ScheduleEntry entry) =>
      SwimCategories.labelFor(entry.category);

  static String sessionTitle(ScheduleEntry entry) =>
      SwimCategories.displayName(category: entry.category, rawName: entry.rawCategory);
}

/// Time-of-day filter buckets for search.
class TimeOfDayFilter {
  static const morning = 'morning';
  static const afternoon = 'afternoon';
  static const evening = 'evening';

  static (String, String)? rangeFor(String filter) => switch (filter) {
        morning => ('05:00', '11:59'),
        afternoon => ('12:00', '16:59'),
        evening => ('17:00', '22:59'),
        _ => null,
      };
}
