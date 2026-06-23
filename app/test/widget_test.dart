import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ottawa_swim_finder/data/scraper/parsers/schedule_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test('schedule parser extracts lane swim from HTML', () {
    const html = '''
    <table>
      <caption>Test Pool - swim and aquafit - March 1 to June 30</caption>
      <tr><th>Activity</th><th>Monday</th></tr>
      <tr><td>Lane swim</td><td>8 - 9 am</td></tr>
    </table>
    ''';

    final entries = ScheduleParser().parse(html, 'test-pool');
    expect(entries, isNotEmpty);
    expect(entries.first.category, 'lane_swim');
  });
}
