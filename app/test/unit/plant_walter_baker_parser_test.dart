import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ottawa_swim_finder/core/utils/ottawa_time.dart';
import 'package:ottawa_swim_finder/data/scraper/parsers/schedule_parser.dart';
import 'package:ottawa_swim_finder/data/services/facility_parser_audit_service.dart';

void main() {
  final parser = ScheduleParser();
  final auditService = FacilityParserAuditService(parser: parser);

  group('Plant Recreation Centre', () {
    late String html;

    setUp(() {
      html = File('test/fixtures/plant_recreation_centre.html').readAsStringSync();
    });

    test('parses Monday sessions from summer table when school-year table ended', () {
      final today = OttawaTime.todayDate();
      final todayDt = DateTime.parse(today);
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final weekdayName = days[todayDt.weekday - 1];
      final tomorrowDt = todayDt.add(const Duration(days: 1));
      final tomorrowName = days[tomorrowDt.weekday - 1];
      final summerHtml = '''
<table>
<caption>Plant Recreation Centre - leisure pool swim - June 1 to August 31</caption>
<thead><tr><th></th><th>$weekdayName</th><th>$tomorrowName</th></tr></thead>
<tbody>
<tr><th>Lane swim</th><td>3 - 5 pm</td><td>3 - 5 pm</td></tr>
</tbody>
</table>
''';
      final entries = parser.parse(summerHtml, 'plant-recreation-centre');

      expect(entries.where((e) => e.date == today).length, greaterThan(0));
      expect(
        entries.where((e) => e.date == today).any((e) => e.rawCategory?.contains('Lane') ?? false),
        isTrue,
      );

      final tomorrow = OttawaTime.formatDate(tomorrowDt);
      expect(entries.where((e) => e.date == tomorrow).length, greaterThan(0));

      final (_, tables) = parser.parseWithTableInfo(html, 'plant-recreation-centre');
      expect(tables.length, 2);
    });

    test('date-column week grid maps today header to today', () {
      final today = OttawaTime.todayDate();
      final todayDt = DateTime.parse(today);
      final headers = List.generate(7, (i) {
        final d = todayDt.add(Duration(days: i));
        const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        const months = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
        ];
        return '${days[d.weekday - 1]} ${months[d.month - 1]} ${d.day}';
      });
      final gridHtml = '''
<table>
<caption>Plant Recreation Centre - leisure pool swim - June 1 to August 31</caption>
<thead><tr><th></th>${headers.map((h) => '<th>$h</th>').join()}</tr></thead>
<tbody>
<tr><th>Lane swim</th>${List.filled(7, '<td>3 - 5 pm</td>').join()}</tr>
</tbody>
</table>
''';
      final entries = parser.parse(gridHtml, 'plant-recreation-centre');
      expect(entries.where((e) => e.date == today).length, greaterThan(0));
    });

    test('audit report lists both season tables', () {
      final report = auditService.audit(
        html: html,
        facilityId: 'plant-recreation-centre',
        facilityName: 'Plant Recreation Centre',
      );
      expect(report.tables.length, 2);
      expect(report.tables.any((t) => t.title.contains('June 1')), isTrue);
      expect(report.sessionCountsByDate.isNotEmpty, isTrue);
    });
  });

  group('Walter Baker Sports Centre', () {
    test('season rollover keeps sessions in current window (Tuesday after Monday)', () {
      final html =
          File('test/fixtures/walter_baker_sports_centre.html').readAsStringSync();
      final entries = parser.parse(html, 'walter-baker-sports-centre');

      final today = OttawaTime.todayDate();
      final tomorrow = OttawaTime.formatDate(DateTime.now().add(const Duration(days: 1)));
      final todayWeekday = DateTime.parse(today).weekday;
      final tomorrowWeekday = DateTime.parse(tomorrow).weekday;

      // Official source: no Monday swims, multiple Tuesday swims.
      if (todayWeekday == DateTime.monday) {
        expect(entries.where((e) => e.date == today).length, 0);
      }
      if (tomorrowWeekday == DateTime.tuesday) {
        expect(
          entries.where((e) => e.date == tomorrow).length,
          greaterThanOrEqualTo(4),
          reason: 'Tuesday column expands into tomorrow',
        );
      } else {
        expect(entries, isNotEmpty);
      }
    });

    test('date-column headers map to specific dates not weekdays', () {
      final html =
          File('test/fixtures/walter_baker_date_columns.html').readAsStringSync();
      final (entries, tables) =
          parser.parseWithTableInfo(html, 'walter-baker-sports-centre');

      expect(tables.single.specialDateColumns.isNotEmpty, isTrue);
      expect(tables.single.dayColumns.isEmpty, isTrue);

      // Date columns must not expand into recurring weekly patterns.
      final sundayDates = entries
          .where((e) => DateTime.parse(e.date!).weekday == DateTime.sunday)
          .map((e) => e.date)
          .toSet();
      expect(sundayDates.length, lessThanOrEqualTo(1));

      expect(entries.any((e) => e.date == '2026-06-22'), isFalse);
      expect(entries.any((e) => e.date == '2026-06-17'), isTrue);
    });
  });

  group('Season expansion regression', () {
    test('cross-year season active in June produces near-term Tuesday sessions', () {
      const html = '''
<table>
<caption>Test Pool - swim - September 9 to June 28</caption>
<thead><tr><th></th><th>Monday</th><th>Tuesday</th></tr></thead>
<tbody>
<tr><th>Lane swim</th><td>n/a</td><td>2 - 4 pm</td></tr>
</tbody>
</table>
''';
      final entries = parser.parse(html, 'test-pool');
      final tomorrow = OttawaTime.formatDate(DateTime.now().add(const Duration(days: 1)));
      final tomorrowWeekday = DateTime.parse(tomorrow).weekday;

      if (tomorrowWeekday == DateTime.tuesday) {
        expect(entries.where((e) => e.date == tomorrow).length, greaterThan(0));
      } else {
        expect(
          entries.where((e) => DateTime.parse(e.date!).weekday == DateTime.tuesday).length,
          greaterThan(0),
        );
      }
    });
  });
}
