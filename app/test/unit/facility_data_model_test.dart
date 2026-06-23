import 'package:flutter_test/flutter_test.dart';
import 'package:ottawa_swim_finder/data/repositories/facility_repository_impl.dart';
import 'package:ottawa_swim_finder/data/services/facility_availability_presenter.dart';
import 'package:ottawa_swim_finder/domain/entities/facility.dart';
import 'package:ottawa_swim_finder/domain/entities/facility_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ottawa_swim_finder/data/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('facility data model rendering', () {
    late AppDatabase db;
    late FacilityRepositoryImpl repo;

    setUp(() async {
      db = AppDatabase.instance;
      await db.close();
      repo = FacilityRepositoryImpl(db);
    });

    test('persists and restores non-swim data models', () async {
      const wading = Facility(
        id: 'owl-park-wading-pool',
        name: 'Owl Park Wading Pool',
        facilityType: FacilityType.wadingPool,
        dataModel: FacilityDataModel.hoursOnly,
        displayStatus: FacilityDisplayStatus.hoursOnly,
        scheduleMode: FacilityScheduleMode.openHoursOnly,
        metadataJson: '{"season":"June 23 to August 15"}',
      );
      const splash = Facility(
        id: 'stonecrest-splash-pad',
        name: 'Stonecrest Park Splash Pad',
        facilityType: FacilityType.splashPad,
        dataModel: FacilityDataModel.hoursOnly,
        displayStatus: FacilityDisplayStatus.hoursOnly,
        scheduleMode: FacilityScheduleMode.openHoursOnly,
      );
      const outdoor = Facility(
        id: 'bearbrook-pool',
        name: 'Bearbrook Pool',
        facilityType: FacilityType.outdoorPool,
        dataModel: FacilityDataModel.mixedSeasonal,
        displayStatus: FacilityDisplayStatus.seasonal,
        scheduleMode: FacilityScheduleMode.seasonalOnly,
      );

      await repo.upsertFacility(wading);
      await repo.upsertFacility(splash);
      await repo.upsertFacility(outdoor);

      final loadedWading = await repo.getFacilityById('owl-park-wading-pool');
      final loadedSplash = await repo.getFacilityById('stonecrest-splash-pad');
      final loadedOutdoor = await repo.getFacilityById('bearbrook-pool');

      expect(loadedWading?.usesSwimScheduleUi, isFalse);
      expect(loadedSplash?.usesSwimScheduleUi, isFalse);
      expect(loadedOutdoor?.usesSwimScheduleUi, isFalse);
      expect(loadedWading?.dataModel, FacilityDataModel.hoursOnly);
      expect(loadedSplash?.facilityType, FacilityType.splashPad);

      expect(
        FacilityAvailabilityPresenter.mapSheetMessage(loadedWading!),
        isNot(contains('Tonight')),
      );
      expect(
        FacilityAvailabilityPresenter.headline(loadedSplash!),
        'Open Hours Only',
      );
    });

    test('infers data model from facility type when column missing', () async {
      const legacy = Facility(
        id: 'legacy-wading',
        name: 'Legacy Wading',
        facilityType: FacilityType.wadingPool,
        dataModel: FacilityDataModel.hoursOnly,
        displayStatus: FacilityDisplayStatus.hoursOnly,
        scheduleMode: FacilityScheduleMode.openHoursOnly,
      );
      await repo.upsertFacility(legacy);

      final loaded = await repo.getFacilityById('legacy-wading');
      expect(loaded?.hasHoursOnly, isTrue);
      expect(loaded?.hasSwimSchedule, isFalse);
    });
  });
}
