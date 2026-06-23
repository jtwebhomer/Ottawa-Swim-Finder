// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:ottawa_swim_finder/core/utils/ottawa_time.dart';
import 'package:ottawa_swim_finder/data/scraper/parsers/schedule_parser.dart';

Future<void> main() async {
  final parser = ScheduleParser();
  final fixtures = <String, String>{
    'plant-recreation-centre': 'test/fixtures/plant_recreation_centre.html',
    'walter-baker-sports-centre': 'test/fixtures/walter_baker_sports_centre.html',
    'plant-recreation-centre-dates':
        'test/fixtures/plant_date_columns.html',
    'walter-baker-sports-centre-dates':
        'test/fixtures/walter_baker_date_columns.html',
  };

  final today = OttawaTime.todayDate();
  final schedules = <Map<String, dynamic>>[];
  final seen = <String>{};

  for (final entry in fixtures.entries) {
    final facilityId = entry.key.replaceAll('-dates', '');
    if (seen.contains(facilityId)) continue;
    final html = await File(entry.value).readAsString();
    final (parsed, _) = parser.parseWithTableInfo(html, facilityId);
    for (final row in parsed) {
      if (row.date != null && row.date!.compareTo(today) < 0) continue;
      schedules.add({
        'facility_id': facilityId,
        'category': row.category,
        'raw_category': row.rawCategory,
        'schedule_type': row.scheduleType,
        'day_of_week': row.dayOfWeek,
        'date': row.date,
        'start_time': row.startTime,
        'end_time': row.endTime,
        'notes': row.notes,
        'date_range_start': row.dateRangeStart,
        'date_range_end': row.dateRangeEnd,
      });
    }
    seen.add(facilityId);
  }

  // Representative weekly template for remaining indoor pools (seed placeholders).
  const indoorIds = [
    'brewer-pool-and-arena',
    'champagne-fitness-centre',
    'jack-purcell-community-centre',
    'lowertown-community-centre-and-pool',
    'bob-macquarrie-recreation-complex-orleans',
    'canterbury-recreation-complex',
    'francois-dupuis-recreation-centre',
    'ray-friel-recreation-complex',
    'splash-wave-pool',
    'st-laurent-complex',
    'deborah-anne-kirwan-pool',
    'sawmill-creek-community-centre-and-pool',
    'nepean-sportsplex',
    'cardelrec-recreation-complex-goulbourn',
    'kanata-leisure-centre-and-wave-pool',
    'minto-recreation-complex-barrhaven',
    'pinecrest-recreation-complex',
    'richcraft-recreation-complex-kanata',
  ];

  for (final facilityId in indoorIds) {
    if (seen.contains(facilityId)) continue;
    for (var day = 0; day < 7; day++) {
      final date = OttawaTime.formatDate(
        DateTime.now().add(Duration(days: day)),
      );
      schedules.addAll([
        {
          'facility_id': facilityId,
          'category': 'lane_swim',
          'raw_category': 'Lane swim',
          'schedule_type': 'expanded',
          'date': date,
          'start_time': '06:30',
          'end_time': '07:30',
          'notes': 'Bundled seed snapshot — verify on ottawa.ca',
        },
        {
          'facility_id': facilityId,
          'category': 'general_swim',
          'raw_category': 'Leisure swim',
          'schedule_type': 'expanded',
          'date': date,
          'start_time': '12:00',
          'end_time': '13:00',
          'notes': 'Bundled seed snapshot — verify on ottawa.ca',
        },
      ]);
    }
  }

  final payload = {
    'version': 1,
    'bundled_at_ms': DateTime(2026, 6, 22).millisecondsSinceEpoch,
    'schedules': schedules,
  };

  final out = File('assets/schedule_seed.json');
  await out.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));
  print('Wrote ${schedules.length} schedule rows to ${out.path}');
}
