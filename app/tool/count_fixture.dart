import 'dart:io';

import 'package:ottawa_swim_finder/core/utils/ottawa_time.dart';
import 'package:ottawa_swim_finder/data/scraper/parsers/schedule_parser.dart';

void main() {
  final parser = ScheduleParser();
  final today = OttawaTime.todayDate();
  final tomorrow =
      OttawaTime.formatDate(DateTime.now().add(const Duration(days: 1)));
  final daysToSat = (DateTime.saturday - DateTime.now().weekday + 7) % 7;
  final sat = OttawaTime.formatDate(
    DateTime.now().add(Duration(days: daysToSat == 0 ? 7 : daysToSat)),
  );

  for (final id in ['plant_recreation_centre', 'walter_baker_sports_centre']) {
    final html = File('test/fixtures/$id.html').readAsStringSync();
    final fid = id.replaceAll('_', '-');
    final entries = parser.parse(html, fid);
    print(
      '$fid total=${entries.length} today=${entries.where((e) => e.date == today).length} '
      'tomorrow=${entries.where((e) => e.date == tomorrow).length} '
      'sat=$sat count=${entries.where((e) => e.date == sat).length}',
    );
  }
}
