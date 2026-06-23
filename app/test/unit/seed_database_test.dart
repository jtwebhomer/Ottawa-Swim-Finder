import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:ottawa_swim_finder/data/database/app_database.dart';
import 'package:ottawa_swim_finder/data/repositories/facility_repository_impl.dart';
import 'package:ottawa_swim_finder/data/repositories/schedule_repository_impl.dart';
import 'package:ottawa_swim_finder/data/repositories/settings_repository_impl.dart';
import 'package:ottawa_swim_finder/data/services/fixture_seed_builder.dart';
import 'package:ottawa_swim_finder/domain/entities/schedule_trust_status.dart';
import 'package:ottawa_swim_finder/data/services/seed_database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return '.';
        }
        return null;
      },
    );
  });

  test('seed loader populates facilities and schedules on first launch', () async {
    final db = AppDatabase.instance;
    await db.close();
    final dbPath = await getDatabasesPath();
    await deleteDatabase(join(dbPath, 'ottawa_swim_finder.db'));

    final facilityRepo = FacilityRepositoryImpl(db);
    final scheduleRepo = ScheduleRepositoryImpl(db);
    final settingsRepo = SettingsRepositoryImpl(db);
    final seedService = SeedDatabaseService(
      facilityRepo: facilityRepo,
      scheduleRepo: scheduleRepo,
      settingsRepo: settingsRepo,
    );

    final seedJson = jsonDecode(
      await rootBundle.loadString(SeedDatabaseService.seedAssetPath),
    ) as Map<String, dynamic>;
    final expectedSessions = (seedJson['schedules'] as List).length;

    final result = await seedService.ensureSeeded(force: true);
    expect(result.loaded, isTrue);
    expect(result.facilityCount, greaterThanOrEqualTo(20));
    expect(result.scheduleCount, expectedSessions);

    final facilities = await facilityRepo.getAllFacilities();
    final schedules = await scheduleRepo.countAllSchedules();
    expect(facilities.length, greaterThanOrEqualTo(20));
    expect(schedules, expectedSessions);

    final fixtureFacilities = facilities.where(
      (f) => f.scheduleTrustStatus == ScheduleTrustStatus.fixture,
    );
    expect(fixtureFacilities.length, FixtureSeedBuilder.fixturePaths.length);
    expect(
      FixtureSeedBuilder.containsPlaceholderNotes(seedJson),
      isFalse,
    );

    final inventory = await scheduleRepo.getCategoryInventory();
    expect(inventory, isNotEmpty);

    final secondPass = await seedService.ensureSeeded();
    expect(secondPass.loaded, isFalse);
  });
}
