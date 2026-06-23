import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ottawa_swim_finder/core/constants/http_constants.dart';
import 'package:ottawa_swim_finder/core/utils/ottawa_time.dart';
import 'package:ottawa_swim_finder/data/scraper/parsers/schedule_parser.dart';

/// Compares live Ottawa HTML vs Dart parser output for audit facilities.
void main() {
  const facilities = [
    ('jack-purcell-community-centre', 'Jack Purcell'),
    ('bob-macquarrie-recreation-complex-orleans', 'Bob MacQuarrie'),
    ('plant-recreation-centre', 'Plant'),
    ('walter-baker-sports-centre', 'Walter Baker'),
    ('richcraft-recreation-complex-kanata', 'Richcraft'),
  ];

  final parser = ScheduleParser();
  final auditReport = <Map<String, dynamic>>[];

  for (final (id, name) in facilities) {
    test('audit $name ($id)', () async {
      final url =
          'https://ottawa.ca/en/recreation-and-parks/facilities/place-listing/$id';
      final response = await http.get(
        Uri.parse(url),
        headers: HttpConstants.headersForUrl(url),
      );

      if (response.statusCode != 200) {
        auditReport.add({
          'facility': name,
          'id': id,
          'error': 'HTTP ${response.statusCode}',
        });
        // Network/bot blocks are environmental — do not fail CI.
        return;
      }

      final html = response.body;
      if (html.toLowerCase().contains('pardon our interruption')) {
        auditReport.add({
          'facility': name,
          'id': id,
          'error': 'Blocked/challenge page',
        });
        return;
      }

      final entries = parser.parse(html, id);
      final today = OttawaTime.todayDate();
      final tomorrow = OttawaTime.formatDate(
        DateTime.now().add(const Duration(days: 1)),
      );

      var weekday = DateTime.now().add(const Duration(days: 1));
      while (weekday.weekday >= 6) {
        weekday = weekday.add(const Duration(days: 1));
      }
      final weekdayStr = OttawaTime.formatDate(weekday);

      final daysToSat = (DateTime.saturday - DateTime.now().weekday + 7) % 7;
      final saturday = OttawaTime.formatDate(
        DateTime.now().add(Duration(days: daysToSat == 0 ? 7 : daysToSat)),
      );

      int countFor(String date) =>
          entries.where((e) => e.date == date).length;

      final facilityReport = {
        'facility': name,
        'id': id,
        'parsed_total': entries.length,
        'today': {'date': today, 'parsed_count': countFor(today)},
        'tomorrow': {'date': tomorrow, 'parsed_count': countFor(tomorrow)},
        'future_weekday': {
          'date': weekdayStr,
          'parsed_count': countFor(weekdayStr),
        },
        'weekend': {'date': saturday, 'parsed_count': countFor(saturday)},
      };
      auditReport.add(facilityReport);

      expect(entries, isNotEmpty, reason: '$name should parse sessions');

      for (final entry in entries) {
        expect(
          entry.startTime.compareTo(entry.endTime),
          lessThan(0),
          reason: '${entry.rawCategory} ${entry.startTime}-${entry.endTime}',
        );
      }

      // Jack Purcell must have evening swims on weekdays in season.
      if (id == 'jack-purcell-community-centre') {
        final todayEntries = entries.where((e) => e.date == today);
        expect(todayEntries, isNotEmpty);
        expect(
          todayEntries.any((e) => e.startTime.compareTo('17:00') >= 0),
          isTrue,
          reason: 'Jack Purcell evening swims expected on $today',
        );
      }
    });
  }

  tearDownAll(() {
    final path = Directory.systemTemp.path +
        '/ottawa_swim_finder_audit_${DateTime.now().millisecondsSinceEpoch}.json';
    File(path).writeAsStringSync(jsonEncode(auditReport));
    // ignore: avoid_print
    print('Audit report written to $path');
    // ignore: avoid_print
    print(jsonEncode(auditReport));
  });
}
