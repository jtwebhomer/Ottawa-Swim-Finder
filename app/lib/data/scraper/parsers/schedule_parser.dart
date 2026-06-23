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

const _monthNames = {
  'january': 1,
  'february': 2,
  'march': 3,
  'april': 4,
  'may': 5,
  'june': 6,
  'july': 7,
  'august': 8,
  'september': 9,
  'october': 10,
  'november': 11,
  'december': 12,
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// Per-table parse metadata for facility audits.
class ParsedScheduleTableInfo {
  const ParsedScheduleTableInfo({
    required this.title,
    this.dateRangeStart,
    this.dateRangeEnd,
    required this.scheduleType,
    required this.headers,
    required this.rawEntryCount,
    required this.dayColumns,
    required this.specialDateColumns,
  });

  final String title;
  final String? dateRangeStart;
  final String? dateRangeEnd;
  final String scheduleType;
  final List<String> headers;
  final int rawEntryCount;
  final Map<int, int> dayColumns;
  final Map<int, String> specialDateColumns;
}

class ScheduleParser {
  ScheduleParser({
    void Function(String facilityId, String category, String cell, String reason)?
        onDroppedTime,
  }) : _onDroppedTime = onDroppedTime;

  final void Function(String facilityId, String category, String cell, String reason)?
      _onDroppedTime;

  /// Last [parseWithTableInfo] call — useful for audits.
  List<ParsedScheduleTableInfo> lastParsedTables = [];

  List<ScheduleEntry> parse(String html, String facilityId) =>
      parseWithTableInfo(html, facilityId).$1;

  (List<ScheduleEntry>, List<ParsedScheduleTableInfo>) parseWithTableInfo(
    String html,
    String facilityId,
  ) {
    final document = html_parser.parse(html);
    final entries = <ScheduleEntry>[];
    final tableInfos = <ParsedScheduleTableInfo>[];

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
        // Date-specific columns must win over weekday substring matches
        // (e.g. "Mon Jun 16" must not map to Monday).
        final parsed = _tryParseDate(headers[i]);
        if (parsed != null) {
          specialDates[i] = parsed;
          scheduleType = 'special';
          continue;
        }
        final dayIdx = _columnDayIndex(headers[i]);
        if (dayIdx != null) {
          dayColumns[i] = dayIdx;
        }
      }

      var tableRawCount = 0;
      for (final row in table.querySelectorAll('tr')) {
        final cells = row.querySelectorAll('th, td');
        if (cells.length < 2) continue;

        final rawCategory = SwimTypeNormalizer.cleanRawActivityLabel(
          cells.first.text.trim(),
        );
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
            tableRawCount++;
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

      if (tableRawCount > 0) {
        tableInfos.add(
          ParsedScheduleTableInfo(
            title: title,
            dateRangeStart: range.$1,
            dateRangeEnd: range.$2,
            scheduleType: scheduleType,
            headers: headers,
            rawEntryCount: tableRawCount,
            dayColumns: Map.from(dayColumns),
            specialDateColumns: Map.from(specialDates),
          ),
        );
      }
    }

    lastParsedTables = tableInfos;
    return (expandRecurring(entries), tableInfos);
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
    final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final horizon = today.add(const Duration(days: 90));

    for (final entry in entries) {
      if (entry.scheduleType == 'special' && entry.date != null) {
        expanded.add(entry);
        continue;
      }
      if (entry.dayOfWeek == null) continue;

      var tableStart = entry.dateRangeStart != null
          ? _dateOnly(DateTime.parse(entry.dateRangeStart!))
          : today;
      var tableEnd = entry.dateRangeEnd != null
          ? _dateOnly(DateTime.parse(entry.dateRangeEnd!))
          : horizon;

      final effectiveStart = tableStart.isAfter(today) ? tableStart : today;
      final effectiveEnd = tableEnd.isAfter(horizon) ? horizon : tableEnd;
      if (effectiveEnd.isBefore(effectiveStart)) continue;

      var current = effectiveStart;
      while (!current.isAfter(effectiveEnd)) {
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

  DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

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

    var start = _parseMonthDay(match.group(1)!);
    var end = _parseMonthDay(match.group(2)!);
    if (start == null || end == null) return (null, null);

    var startDt = start;
    var endDt = end;

    if (endDt.isBefore(startDt)) {
      endDt = DateTime(endDt.year + 1, endDt.month, endDt.day);
    }

    final today = _dateOnly(DateTime.now());
    // Cross-year season (e.g. Sept–June): in Jan–Jun the start month is last year.
    if (today.isBefore(startDt) && endDt.year == startDt.year + 1) {
      startDt = DateTime(startDt.year - 1, startDt.month, startDt.day);
      endDt = DateTime(endDt.year - 1, endDt.month, endDt.day);
    }

    // Entire season ended — advance to the next cycle.
    while (endDt.isBefore(today)) {
      startDt = DateTime(startDt.year + 1, startDt.month, startDt.day);
      endDt = DateTime(endDt.year + 1, endDt.month, endDt.day);
    }

    return (OttawaTime.formatDate(startDt), OttawaTime.formatDate(endDt));
  }

  DateTime? _parseMonthDay(String text) {
    final match = RegExp(r'([A-Za-z]+)\s+(\d{1,2})').firstMatch(text.trim());
    if (match == null) return null;
    final monthKey = match.group(1)!.toLowerCase();
    final month = _monthNames[monthKey] ??
        _monthNames[monthKey.length >= 3 ? monthKey.substring(0, 3) : monthKey];
    if (month == null) return null;
    final day = int.parse(match.group(2)!);
    return DateTime(DateTime.now().year, month, day);
  }

  int? _columnDayIndex(String header) {
    final lower = header.toLowerCase().trim();
    if (_containsMonthName(lower)) return null;

    for (var i = 0; i < _dayNames.length; i++) {
      final day = _dayNames[i];
      final short = day.substring(0, 3);
      if (lower == day ||
          lower == short ||
          lower.startsWith('$day ') ||
          lower.startsWith('$short ')) {
        return i + 1;
      }
    }
    return null;
  }

  bool _containsMonthName(String lower) {
    for (final key in _monthNames.keys) {
      if (key.length <= 3) {
        if (RegExp('\\b$key\\b').hasMatch(lower)) return true;
      } else if (lower.contains(key)) {
        return true;
      }
    }
    return RegExp(r'\b[A-Za-z]+\s+\d{1,2}\b').hasMatch(lower) &&
        _parseMonthDay(
              RegExp(r'([A-Za-z]+\s+\d{1,2})').firstMatch(lower)?.group(1) ?? '',
            ) !=
            null;
  }

  String? _tryParseDate(String header) {
    final match = RegExp(r'\b([A-Za-z]+)\s+(\d{1,2})\b').firstMatch(header.trim());
    if (match == null) return null;

    final monthKey = match.group(1)!.toLowerCase();
    final month = _monthNames[monthKey] ??
        _monthNames[monthKey.length >= 3 ? monthKey.substring(0, 3) : monthKey];
    if (month == null) return null;

    final day = int.parse(match.group(2)!);
    var year = DateTime.now().year;
    var candidate = DateTime(year, month, day);

    // Headers for a week in the recent past belong to the current year context.
    final today = _dateOnly(DateTime.now());
    if (candidate.isBefore(today.subtract(const Duration(days: 45)))) {
      year += 1;
      candidate = DateTime(year, month, day);
    }

    return OttawaTime.formatDate(candidate);
  }
}
