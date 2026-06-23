import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/schedule_entry.dart';

/// Export swim sessions to Google Calendar or .ics files.
class CalendarExportService {
  String buildIcs({
    required ScheduleEntry entry,
    required String title,
    String? facilityName,
    String? address,
  }) {
    if (entry.date == null) {
      throw ArgumentError('Cannot export recurring pattern without a date');
    }
    final start = _toIcsDateTime(entry.date!, entry.startTime);
    final end = _toIcsDateTime(entry.date!, entry.endTime);
    final uid = '${entry.facilityId}_${entry.date}_${entry.startTime}@ottawaswimfinder';
    final location = _escapeIcs([facilityName, address].whereType<String>().join(', '));
    final summary = _escapeIcs(title);
    final desc = _escapeIcs(
      '${SwimCategories.labelFor(entry.category)} at ${facilityName ?? entry.facilityId}',
    );

    return '''BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Ottawa Swim Finder//EN
CALSCALE:GREGORIAN
BEGIN:VEVENT
UID:$uid
DTSTAMP:${_formatIcsUtc(DateTime.now())}
DTSTART:$start
DTEND:$end
SUMMARY:$summary
DESCRIPTION:$desc
LOCATION:$location
END:VEVENT
END:VCALENDAR''';
  }

  Uri googleCalendarUrl({
    required ScheduleEntry entry,
    required String title,
    String? facilityName,
    String? address,
  }) {
    if (entry.date == null) {
      throw ArgumentError('Cannot export without a date');
    }
    final start = _googleDateTime(entry.date!, entry.startTime);
    final end = _googleDateTime(entry.date!, entry.endTime);
    final details =
        '${SwimCategories.labelFor(entry.category)} at ${facilityName ?? entry.facilityId}';
    final location = [facilityName, address].whereType<String>().join(', ');

    return Uri.https('calendar.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': title,
      'dates': '$start/$end',
      'details': details,
      'location': location,
    });
  }

  Future<void> openGoogleCalendar(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not open Google Calendar');
    }
  }

  String _toIcsDateTime(String date, String time) {
    final d = date.split('-');
    final t = time.split(':');
    return '${d[0]}${d[1]}${d[2]}T${t[0].padLeft(2, '0')}${t[1].padLeft(2, '0')}00';
  }

  String _googleDateTime(String date, String time) {
    final d = date.replaceAll('-', '');
    final t = time.replaceAll(':', '');
    return '${d}T${t.padRight(6, '0')}';
  }

  String _formatIcsUtc(DateTime dt) =>
      DateFormat("yyyyMMdd'T'HHmmss'Z'").format(dt.toUtc());

  String _escapeIcs(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll('\n', '\\n').replaceAll(',', '\\,');
}
