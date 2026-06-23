/// Ottawa-local schedule time parsing and comparison.
///
/// All schedule times are stored as zero-padded 24h `HH:MM` strings in
/// America/Toronto local time (Ottawa observes Toronto time).
class OttawaTime {
  OttawaTime._();

  static const timeRangePattern =
      r'((?:\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?)|noon|midnight)\s*(?:[-–]|to)\s*'
      r'((?:\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?)|noon|midnight)';

  /// Parse a cell's time ranges. Returns `(start, end, notes)` tuples.
  static List<(String, String, String?)> extractTimeRanges(String cellText) {
    final trimmed = cellText.trim();
    if (trimmed.isEmpty ||
        trimmed.toLowerCase() == 'n/a' ||
        trimmed == '-') {
      return [];
    }

    final notes =
        trimmed.toLowerCase().contains('play free') ? 'Play Free' : null;
    final regex = RegExp(timeRangePattern, caseSensitive: false);

    final results = <(String, String, String?)>[];
    for (final match in regex.allMatches(trimmed)) {
      final range = parseRange(match.group(1)!, match.group(2)!);
      if (range != null) {
        results.add((range.$1, range.$2, notes));
      }
    }
    return results;
  }

  /// Parse a single start/end pair into 24h `HH:MM` strings.
  static (String, String)? parseRange(String startRaw, String endRaw) {
    final endParsed = _parseSingle(endRaw, reference: null);
    if (endParsed == null) return null;

    final startParsed = _parseSingle(
      startRaw,
      reference: endRaw,
      endMinutes: endParsed,
    );
    if (startParsed == null) return null;

    if (startParsed >= endParsed) return null;

    return (_formatMinutes(startParsed), _formatMinutes(endParsed));
  }

  static int? _parseSingle(
    String raw, {
    required String? reference,
    int? endMinutes,
  }) {
    final normalized = _normalizeTimeToken(raw.trim().toLowerCase());
    final cleaned = normalized.replaceAll('.', '');
    final hasPeriod = cleaned.contains('am') || cleaned.contains('pm');

    final match = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)?').firstMatch(cleaned);
    if (match == null) return null;

    final hour12 = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2) ?? '0');
    var period = match.group(3);

    if (!hasPeriod && reference != null) {
      period = _inferPeriodForStart(
        hour12: hour12,
        reference: reference,
        endMinutes: endMinutes,
      );
    }

    if (period == null && !hasPeriod) {
      // Bare 24h-style hours (e.g. "18:00") when no am/pm on either side.
      if (hour12 >= 13) {
        return hour12 * 60 + minute;
      }
      return null;
    }

    var hour24 = hour12 % 12;
    if (period == 'pm') hour24 += 12;
    if (period == 'am' && hour12 == 12) hour24 = 0;

    return hour24 * 60 + minute;
  }

  static String _normalizeTimeToken(String raw) {
    if (raw == 'noon') return '12 pm';
    if (raw == 'midnight') return '12 am';
    return raw;
  }

  static String? _inferPeriodForStart({
    required int hour12,
    required String reference,
    int? endMinutes,
  }) {
    final ref = reference.trim().toLowerCase().replaceAll('.', '');
    final refMatch = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)?').firstMatch(ref);
    if (refMatch == null) return null;

    final refHour = int.parse(refMatch.group(1)!);
    final refMinute = int.parse(refMatch.group(2) ?? '0');
    var refPeriod = refMatch.group(3);

    if (refPeriod == null) return null;

    var refHour24 = refHour % 12;
    if (refPeriod == 'pm') refHour24 += 12;
    if (refPeriod == 'am' && refHour == 12) refHour24 = 0;
    final resolvedEnd = endMinutes ?? (refHour24 * 60 + refMinute);

    // Ottawa.ca often writes "11 - 1 pm" (start is AM when start hour > end hour on 12h clock).
    if (refPeriod == 'pm' && hour12 > refHour) {
      final amStart = (hour12 == 12 ? 0 : hour12) * 60;
      if (amStart < resolvedEnd && resolvedEnd - amStart <= 8 * 60) {
        return 'am';
      }
    }

    // Try both AM and PM candidates; pick a valid same-day window (15 min – 8 hr).
    final candidates = <String>[];
    if (refPeriod == 'pm') candidates.addAll(['am', 'pm']);
    if (refPeriod == 'am') candidates.addAll(['am', 'pm']);

    for (final candidate in candidates) {
      var h = hour12 % 12;
      if (candidate == 'pm') h += 12;
      if (candidate == 'am' && hour12 == 12) h = 0;
      final start = h * 60;
      final duration = resolvedEnd - start;
      if (duration >= 15 && duration <= 8 * 60) {
        return candidate;
      }
    }

    return refPeriod;
  }

  static String _formatMinutes(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// Current Ottawa-local date as `YYYY-MM-DD`.
  static String todayDate() {
    final now = DateTime.now();
    return formatDate(now);
  }

  /// Current Ottawa-local time as zero-padded `HH:MM`.
  static String nowTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  static String formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  static String formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  /// Whether [time] (`HH:MM`) falls in `[start, end)` on the same calendar day.
  static bool isActiveAt({
    required String start,
    required String end,
    required String time,
  }) =>
      start.compareTo(time) <= 0 && end.compareTo(time) > 0;

  static bool isUpcomingAt({
    required String start,
    required String time,
  }) =>
      start.compareTo(time) > 0;

  static bool isRemainingToday({
    required String end,
    required String time,
  }) =>
      end.compareTo(time) > 0;
}
