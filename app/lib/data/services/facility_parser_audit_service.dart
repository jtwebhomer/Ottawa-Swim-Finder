import '../../core/utils/ottawa_time.dart';
import '../scraper/parsers/schedule_parser.dart';

/// Facility-level parser audit report for diagnostics and tooling.
class FacilityParserAuditReport {
  const FacilityParserAuditReport({
    required this.facilityId,
    required this.facilityName,
    required this.tables,
    required this.sessionCountsByDate,
    required this.totalExpandedSessions,
    required this.futureSessionCount,
  });

  final String facilityId;
  final String facilityName;
  final List<FacilityTableAudit> tables;
  final Map<String, int> sessionCountsByDate;
  final int totalExpandedSessions;
  final int futureSessionCount;
}

class FacilityTableAudit {
  const FacilityTableAudit({
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

  String get dateRangeLabel =>
      dateRangeStart != null && dateRangeEnd != null
          ? '$dateRangeStart → $dateRangeEnd'
          : 'No season range';
}

class FacilityParserAuditService {
  FacilityParserAuditService({ScheduleParser? parser})
      : _parser = parser ?? ScheduleParser();

  final ScheduleParser _parser;

  FacilityParserAuditReport audit({
    required String html,
    required String facilityId,
    required String facilityName,
    int dayHorizon = 14,
  }) {
    final (entries, tables) = _parser.parseWithTableInfo(html, facilityId);
    final today = OttawaTime.todayDate();
    final todayDt = DateTime.parse(today);

    final counts = <String, int>{};
    for (var i = 0; i < dayHorizon; i++) {
      final d = OttawaTime.formatDate(todayDt.add(Duration(days: i)));
      final c = entries.where((e) => e.date == d).length;
      if (c > 0) counts[d] = c;
    }

    final futureCount =
        entries.where((e) => e.date != null && e.date!.compareTo(today) > 0).length;

    return FacilityParserAuditReport(
      facilityId: facilityId,
      facilityName: facilityName,
      tables: tables
          .map(
            (t) => FacilityTableAudit(
              title: t.title,
              dateRangeStart: t.dateRangeStart,
              dateRangeEnd: t.dateRangeEnd,
              scheduleType: t.scheduleType,
              headers: t.headers,
              rawEntryCount: t.rawEntryCount,
              dayColumns: t.dayColumns,
              specialDateColumns: t.specialDateColumns,
            ),
          )
          .toList(),
      sessionCountsByDate: counts,
      totalExpandedSessions: entries.length,
      futureSessionCount: futureCount,
    );
  }

  String formatReport(FacilityParserAuditReport report) {
    final buf = StringBuffer()
      ..writeln('Facility: ${report.facilityName}')
      ..writeln('Total sessions: ${report.totalExpandedSessions}')
      ..writeln('Future sessions: ${report.futureSessionCount}')
      ..writeln('Season tables: ${report.tables.length}');

    for (final table in report.tables) {
      buf
        ..writeln('\nTable: ${table.title}')
        ..writeln('  Season: ${table.dateRangeLabel}')
        ..writeln('  Type: ${table.scheduleType}')
        ..writeln('  Raw entries: ${table.rawEntryCount}')
        ..writeln('  Weekday cols: ${table.dayColumns}')
        ..writeln('  Date cols: ${table.specialDateColumns}');
    }

    buf.writeln('\nSessions by date (next ${report.sessionCountsByDate.length} days with data):');
    for (final e in report.sessionCountsByDate.entries) {
      buf.writeln('  ${e.key}: ${e.value}');
    }
    return buf.toString();
  }
}
