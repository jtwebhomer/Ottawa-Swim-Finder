import '../../core/logging/app_logger.dart';
import '../../core/utils/ottawa_time.dart';
import '../../domain/entities/schedule_entry.dart';
import '../scraper/parsers/schedule_parser.dart';

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
    List<ParsedScheduleTableInfo> tables = const [],
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

    _checkParseValidation(
      facilityId: facilityId,
      facilityName: facilityName,
      entries: entries,
      tables: tables,
      warnings: warnings,
    );

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

  static void _checkParseValidation({
    required String facilityId,
    required String facilityName,
    required List<ScheduleEntry> entries,
    required List<ParsedScheduleTableInfo> tables,
    required List<String> warnings,
  }) {
    final today = OttawaTime.todayDate();
    final horizon = OttawaTime.formatDate(
      DateTime.parse(today).add(const Duration(days: 13)),
    );

    var next14 = 0;
    for (final entry in entries) {
      final d = entry.date;
      if (d == null) continue;
      if (d.compareTo(today) >= 0 && d.compareTo(horizon) <= 0) {
        next14++;
      }
    }

    final futureCount =
        entries.where((e) => e.date != null && e.date!.compareTo(today) > 0).length;
    if (futureCount > 100 && next14 == 0) {
      warnings.add(
        '[future_gap] $facilityName: $futureCount future sessions but none in next 14 days',
      );
    }

    final hasWeekdayCols = tables.any((t) => t.dayColumns.isNotEmpty);
    if (hasWeekdayCols && next14 == 0 && entries.isNotEmpty) {
      warnings.add(
        '[empty_weekday_expansion] $facilityName: weekday columns present but no sessions in next 14 days',
      );
    }

    for (var i = 0; i < tables.length; i++) {
      for (var j = i + 1; j < tables.length; j++) {
        final a = tables[i];
        final b = tables[j];
        if (a.dateRangeStart == null ||
            a.dateRangeEnd == null ||
            b.dateRangeStart == null ||
            b.dateRangeEnd == null) {
          continue;
        }
        if (_rangesOverlap(
          a.dateRangeStart!,
          a.dateRangeEnd!,
          b.dateRangeStart!,
          b.dateRangeEnd!,
        )) {
          warnings.add(
            '[season_overlap] $facilityName: "${a.title}" overlaps "${b.title}" '
            '(${a.dateRangeStart}–${a.dateRangeEnd} vs ${b.dateRangeStart}–${b.dateRangeEnd})',
          );
        }
      }
    }

    for (final entry in entries) {
      if (entry.date == null ||
          entry.dateRangeStart == null ||
          entry.dateRangeEnd == null) {
        continue;
      }
      if (entry.date!.compareTo(entry.dateRangeStart!) < 0 ||
          entry.date!.compareTo(entry.dateRangeEnd!) > 0) {
        warnings.add(
          '[outside_season] $facilityName: ${entry.date} outside '
          '${entry.dateRangeStart}–${entry.dateRangeEnd} (${entry.rawCategory})',
        );
        break;
      }
    }
  }

  static bool _rangesOverlap(String aStart, String aEnd, String bStart, String bEnd) {
    return aStart.compareTo(bEnd) <= 0 && bStart.compareTo(aEnd) <= 0;
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
