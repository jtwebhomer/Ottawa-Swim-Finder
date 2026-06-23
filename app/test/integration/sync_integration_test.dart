import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ottawa_swim_finder/data/database/app_database.dart';
import 'package:ottawa_swim_finder/data/repositories/facility_repository_impl.dart';
import 'package:ottawa_swim_finder/data/repositories/schedule_repository_impl.dart';
import 'package:ottawa_swim_finder/domain/entities/facility.dart';
import 'package:ottawa_swim_finder/domain/entities/schedule_entry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('facility and schedule persistence integration', () async {
    final db = AppDatabase.instance;
    await db.close();

    final facilityRepo = FacilityRepositoryImpl(db);
    final scheduleRepo = ScheduleRepositoryImpl(db);

    await facilityRepo.upsertFacility(
      const Facility(
        id: 'kanata-leisure-centre-and-wave-pool',
        name: 'Kanata Leisure Centre and Wave Pool',
        address: '70 Aird Place',
        latitude: 45.308,
        longitude: -75.918,
        region: 'west',
      ),
    );

    await scheduleRepo.deleteSchedulesForFacility('kanata-leisure-centre-and-wave-pool');
    await scheduleRepo.upsertSchedules('kanata-leisure-centre-and-wave-pool', [
      const ScheduleEntry(
        facilityId: 'kanata-leisure-centre-and-wave-pool',
        category: 'lane_swim',
        scheduleType: 'expanded',
        date: '2026-06-22',
        startTime: '08:00',
        endTime: '09:00',
      ),
      const ScheduleEntry(
        facilityId: 'kanata-leisure-centre-and-wave-pool',
        category: 'public_swim',
        scheduleType: 'expanded',
        date: '2026-06-22',
        startTime: '17:00',
        endTime: '18:00',
      ),
    ]);

    final laneResults = await scheduleRepo.searchSchedules(
      categories: ['lane_swim'],
      facilityId: 'kanata-leisure-centre-and-wave-pool',
      date: '2026-06-22',
    );
    expect(laneResults.length, 1);

    final allForFacility = await scheduleRepo.getSchedulesForFacility(
      'kanata-leisure-centre-and-wave-pool',
      date: '2026-06-22',
    );
    expect(allForFacility.length, 2);

    await facilityRepo.toggleFavorite('kanata-leisure-centre-and-wave-pool', true);
    final favorites = await facilityRepo.getFavorites();
    expect(favorites.length, 1);
    expect(favorites.first.isFavorite, isTrue);
  });
}
