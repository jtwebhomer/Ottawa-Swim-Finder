import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/utils/ottawa_time.dart';
import '../../../domain/entities/schedule_entry.dart';
import 'category_normalizer.dart';

const _dayNames = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

class ScheduleParser {
  ScheduleParser({void Function(String facilityId, String category, String cell, String reason)? onDroppedTime})
      : _onDroppedTime = onDroppedTime;

  final void Function(String facilityId, String category, String cell, String reason)? _onDroppedTime;

  List<ScheduleEntry> parse(String html, String facilityId) {
    final document = html_parser.parse(html);
    final entries = <ScheduleEntry>[];

    for (final table in document.querySelectorAll('table')) {
      final title = _tableTitle(table);
      if (!_isSwimTable(title)) continue;

      final range = _parseDateRange(title);
      var scheduleType = range.$1 != null ? 'recurring' : 'special';

      final headerRow = table.querySelector('tr');
      final headers =
          headerRow?.querySelectorAll('th').map((e) => e.text.trim()).toList() ??
              <String>[];
      if (headers.length < 2) continue;

      final dayColumns = <int, int>{};
      final specialDates = <int, String>{};

      for (var i = 0; i < headers.length; i++) {
        final dayIdx = _columnDayIndex(headers[i]);
        if (dayIdx != null) {
          dayColumns[i] = dayIdx;
        } else {
          final parsed = _tryParseDate(headers[i]);
          if (parsed != null) {
            specialDates[i] = parsed;
            scheduleType = 'special';
          }
        }
      }

      for (final row in table.querySelectorAll('tr')) {
        final cells = row.querySelectorAll('th, td');
        if (cells.length < 2) continue;

        final rawCategory = cells.first.text.trim();
        if (rawCategory.isEmpty ||
            _dayNames.contains(rawCategory.toLowerCase()) ||
            !isSwimRow(rawCategory)) {
          continue;
        }

        final category = normalizeSwimCategory(rawCategory);

        for (var col = 1; col < cells.length; col++) {
          final cellIdx = col;
          final cellText = cells[col].text.trim();
          if (cellText.isEmpty) continue;

          final times = OttawaTime.extractTimeRanges(cellText);
          if (times.isEmpty && _looksLikeScheduleCell(cellText)) {
            _onDroppedTime?.call(
              facilityId,
              rawCategory,
              cellText,
              'no parseable time range',
            );
            appLogger.w(
              '[schedule-parser] unparsed cell facility=$facilityId '
              'category=$rawCategory text="$cellText"',
            );
            continue;
          }

          for (final slot in times) {
            entries.add(
              ScheduleEntry(
                facilityId: facilityId,
                category: category,
                rawCategory: rawCategory,
                scheduleType: scheduleType,
                dayOfWeek: dayColumns[cellIdx],
                date: specialDates[cellIdx],
                startTime: slot.$1,
                endTime: slot.$2,
                notes: slot.$3,
                dateRangeStart: range.$1,
                dateRangeEnd: range.$2,
              ),
            );
          }
        }
      }
    }

    return expandRecurring(entries);
  }

  bool _looksLikeScheduleCell(String text) {
    final lower = text.toLowerCase();
    return lower != 'n/a' &&
        lower != '-' &&
        RegExp(r'\d').hasMatch(text) &&
        (lower.contains('am') || lower.contains('pm') || lower.contains(':'));
  }

  List<ScheduleEntry> expandRecurring(List<ScheduleEntry> entries) {
    final expanded = <ScheduleEntry>[];
    final today = DateTime.now();
    final horizon = today.add(const Duration(days: 90));

    for (final entry in entries) {
      if (entry.scheduleType == 'special' && entry.date != null) {
        expanded.add(entry);
        continue;
      }
      if (entry.dayOfWeek == null) continue;

      final tableStart = entry.dateRangeStart != null
          ? DateTime.parse(entry.dateRangeStart!)
          : today;
      var tableEnd =
          entry.dateRangeEnd != null ? DateTime.parse(entry.dateRangeEnd!) : horizon;

      // Season ended: roll forward until the range covers today.
      while (tableEnd.isBefore(today)) {
        tableEnd = DateTime(tableEnd.year + 1, tableEnd.month, tableEnd.day);
      }

      var current = tableStart.isAfter(today) ? tableStart : today;
      final endBound = tableEnd.isBefore(horizon) ? tableEnd : horizon;
      if (endBound.isBefore(current)) continue;

      while (!current.isAfter(endBound)) {
        if (current.weekday == entry.dayOfWeek) {
          expanded.add(
            ScheduleEntry(
              facilityId: entry.facilityId,
              category: entry.category,
              rawCategory: entry.rawCategory,
              scheduleType: 'expanded',
              dayOfWeek: entry.dayOfWeek,
              date: OttawaTime.formatDate(current),
              startTime: entry.startTime,
              endTime: entry.endTime,
              notes: entry.notes,
              dateRangeStart: entry.dateRangeStart,
              dateRangeEnd: entry.dateRangeEnd,
            ),
          );
        }
        current = current.add(const Duration(days: 1));
      }
    }

    return expanded;
  }

  String _tableTitle(Element table) {
    final caption = table.querySelector('caption')?.text.trim();
    if (caption != null && caption.isNotEmpty) return caption;
    final prev = table.previousElementSibling;
    if (prev != null) return prev.text.trim();
    return '';
  }

  bool _isSwimTable(String title) {
    final lower = title.toLowerCase();
    return lower.contains('swim') || lower.contains('aquafit');
  }

  (String?, String?) _parseDateRange(String title) {
    final regex = RegExp(
      r'([A-Za-z]+\s+\d{1,2})\s+to\s+([A-Za-z]+\s+\d{1,2})',
      caseSensitive: false,
    );
    final match = regex.firstMatch(title);
    if (match == null) return (null, null);

    try {
      final year = DateTime.now().year;
      final start = DateTime.parse('${match.group(1)} $year');
      var end = DateTime.parse('${match.group(2)} $year');
      if (end.isBefore(start)) {
        end = DateTime(end.year + 1, end.month, end.day);
      }
      return (OttawaTime.formatDate(start), OttawaTime.formatDate(end));
    } catch (_) {
      return (null, null);
    }
  }

  int? _columnDayIndex(String header) {
    final lower = header.toLowerCase();
    for (var i = 0; i < _dayNames.length; i++) {
      if (lower.contains(_dayNames[i]) || lower.contains(_dayNames[i].substring(0, 3))) {
        return i + 1;
      }
    }
    return null;
  }

  String? _tryParseDate(String header) {
    final months = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    final match = RegExp(r'([A-Za-z]+)\s+(\d{1,2})').firstMatch(header);
    if (match == null) return null;
    final monthStr = match.group(1)!.toLowerCase().substring(0, 3);
    final month = months[monthStr];
    if (month == null) return null;
    final day = int.parse(match.group(2)!);
    final year = DateTime.now().year;
    return OttawaTime.formatDate(DateTime(year, month, day));
  }
}
