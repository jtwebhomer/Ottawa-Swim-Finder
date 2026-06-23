import 'package:flutter_test/flutter_test.dart';
import 'package:ottawa_swim_finder/domain/entities/facility.dart';
import 'package:ottawa_swim_finder/domain/entities/schedule_entry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ottawa_swim_finder/core/utils/ottawa_time.dart';
import 'package:ottawa_swim_finder/data/database/app_database.dart';
import 'package:ottawa_swim_finder/data/repositories/facility_repository_impl.dart';
import 'package:ottawa_swim_finder/data/repositories/schedule_repository_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Facility pin mapping', () {
    late ScheduleRepositoryImpl scheduleRepo;

    setUp(() async {
      final db = AppDatabase.instance;
      await db.close();

      final facilityRepo = FacilityRepositoryImpl(db);
      scheduleRepo = ScheduleRepositoryImpl(db);

      await facilityRepo.upsertFacility(
        const Facility(
          id: 'plant-recreation-centre',
          name: 'Plant Recreation Centre',
          address: '930 Somerset Street West',
        ),
      );
      await facilityRepo.upsertFacility(
        const Facility(
          id: 'brewer-pool-and-arena',
          name: 'Brewer Pool and Arena',
          address: '100 Brewer Way',
        ),
      );

      final today = OttawaTime.todayDate();
      await scheduleRepo.replaceSchedulesForFacility('plant-recreation-centre', [
        ScheduleEntry(
          facilityId: 'plant-recreation-centre',
          category: 'lane_swim',
          rawCategory: 'Lane swim',
          scheduleType: 'expanded',
          date: today,
          startTime: '08:00',
          endTime: '09:00',
        ),
      ]);
      await scheduleRepo.replaceSchedulesForFacility('brewer-pool-and-arena', [
        ScheduleEntry(
          facilityId: 'brewer-pool-and-arena',
          category: 'general_swim',
          rawCategory: 'Public swim',
          scheduleType: 'expanded',
          date: today,
          startTime: '17:00',
          endTime: '18:00',
        ),
      ]);

    });

    test('getTimelineForDate scopes by facilityId', () async {
      final today = OttawaTime.todayDate();
      final plantRows = await scheduleRepo.getTimelineForDate(
        today,
        facilityId: 'plant-recreation-centre',
      );
      final brewerRows = await scheduleRepo.getTimelineForDate(
        today,
        facilityId: 'brewer-pool-and-arena',
      );

      expect(plantRows.every((s) => s.facilityId == 'plant-recreation-centre'), isTrue);
      expect(brewerRows.every((s) => s.facilityId == 'brewer-pool-and-arena'), isTrue);
    });

    test('facility schedules do not cross-contaminate between facilities', () async {
      final today = OttawaTime.todayDate();
      final plant = await scheduleRepo.getSchedulesForFacilityBetween(
        facilityId: 'plant-recreation-centre',
        startDate: today,
        endDate: today,
      );
      final brewer = await scheduleRepo.getSchedulesForFacilityBetween(
        facilityId: 'brewer-pool-and-arena',
        startDate: today,
        endDate: today,
      );

      expect(plant.single.rawCategory, 'Lane swim');
      expect(brewer.single.rawCategory, 'Public swim');
    });
  });
}
