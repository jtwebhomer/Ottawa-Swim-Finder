import '../../core/logging/app_logger.dart';
import '../../core/utils/ottawa_time.dart';
import '../../domain/entities/schedule_entry.dart';

class ScheduleSanityReport {
  const ScheduleSanityReport({
    required this.warnings,
    required this.todayEntryCount,
    required this.eveningEntryCount,
    required this.invalidTimeRanges,
  });

  final List<String> warnings;
  final int todayEntryCount;
  final int eveningEntryCount;
  final int invalidTimeRanges;

  bool get hasIssues => warnings.isNotEmpty;
}

/// Detects suspicious schedule data after parsing or sync.
class ScheduleSanityChecker {
  ScheduleSanityReport check({
    required String facilityId,
    required String facilityName,
    required List<ScheduleEntry> entries,
    required int htmlSwimMentions,
  }) {
    final today = OttawaTime.todayDate();
    final todayEntries = entries.where((e) => e.date == today).toList();
    final eveningEntries = todayEntries
        .where((e) => e.startTime.compareTo('17:00') >= 0)
        .toList();

    final warnings = <String>[];
    var invalidRanges = 0;

    for (final entry in entries) {
      if (entry.startTime.compareTo(entry.endTime) >= 0) {
        invalidRanges++;
        warnings.add(
          '$facilityId invalid range ${entry.startTime}-${entry.endTime} '
          '(${entry.rawCategory ?? entry.category})',
        );
      }
    }

    if (htmlSwimMentions >= 3 && todayEntries.isEmpty) {
      warnings.add(
        '$facilityName ($facilityId): HTML mentions swims ($htmlSwimMentions) '
        'but parser produced 0 sessions for $today',
      );
    }

    if (htmlSwimMentions >= 5 &&
        eveningEntries.isEmpty &&
        todayEntries.isNotEmpty) {
      warnings.add(
        '$facilityName ($facilityId): sessions exist today but none after 17:00 '
        '(possible AM/PM parse issue)',
      );
    }

    if (warnings.isNotEmpty) {
      for (final warning in warnings.take(5)) {
        appLogger.w('[schedule-sanity] $warning');
      }
      if (warnings.length > 5) {
        appLogger.w(
          '[schedule-sanity] ${warnings.length - 5} more warnings for $facilityId',
        );
      }
    }

    return ScheduleSanityReport(
      warnings: warnings,
      todayEntryCount: todayEntries.length,
      eveningEntryCount: eveningEntries.length,
      invalidTimeRanges: invalidRanges,
    );
  }

  static int countSwimMentions(String html) {
    final lower = html.toLowerCase();
    var count = 0;
    for (final pattern in ['swim', 'aquafit']) {
      var index = 0;
      while (true) {
        index = lower.indexOf(pattern, index);
        if (index == -1) break;
        count++;
        index += pattern.length;
      }
    }
    return count;
  }
}
