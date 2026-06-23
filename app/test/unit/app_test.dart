import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ottawa_swim_finder/data/database/app_database.dart';
import 'package:ottawa_swim_finder/data/repositories/facility_repository_impl.dart';
import 'package:ottawa_swim_finder/data/repositories/schedule_repository_impl.dart';
import 'package:ottawa_swim_finder/domain/entities/facility.dart';
import 'package:ottawa_swim_finder/domain/entities/schedule_entry.dart';
import 'package:ottawa_swim_finder/data/scraper/parsers/schedule_parser.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('ScheduleParser', () {
    test('parses lane swim times from HTML table', () {
      const html = '''
      <table>
        <caption>Test Pool - swim and aquafit - March 1 to June 30</caption>
        <tr><th>Activity</th><th>Monday</th></tr>
        <tr><td>Lane swim</td><td>8 - 9 am</td></tr>
      </table>
      ''';

      final parser = ScheduleParser();
      final entries = parser.parse(html, 'test-pool');
      expect(entries, isNotEmpty);
      expect(entries.first.category, 'lane_swim');
      expect(entries.first.startTime, '08:00');
    });
  });

  group('Repositories', () {
    late AppDatabase db;
    late FacilityRepositoryImpl facilityRepo;
    late ScheduleRepositoryImpl scheduleRepo;

    setUp(() async {
      db = AppDatabase.instance;
      await db.close();
      facilityRepo = FacilityRepositoryImpl(db);
      scheduleRepo = ScheduleRepositoryImpl(db);
    });

    test('upsert and retrieve facility', () async {
      await facilityRepo.upsertFacility(
        const Facility(id: 'test', name: 'Test Pool', address: '123 Main'),
      );
      final facility = await facilityRepo.getFacilityById('test');
      expect(facility?.name, 'Test Pool');
    });

    test('search schedules by category', () async {
      await facilityRepo.upsertFacility(
        const Facility(id: 'test', name: 'Test Pool'),
      );
      await scheduleRepo.deleteSchedulesForFacility('test');
      await scheduleRepo.upsertSchedules('test', [
        const ScheduleEntry(
          facilityId: 'test',
          category: 'lane_swim',
          scheduleType: 'expanded',
          date: '2099-06-22',
          startTime: '08:00',
          endTime: '09:00',
        ),
      ]);

      final results = await scheduleRepo.searchSchedules(
        categories: ['lane_swim'],
        facilityId: 'test',
        date: '2099-06-22',
      );
      expect(results.length, 1);
    });
  });
}
