import 'package:get_it/get_it.dart';

import '../data/database/app_database.dart';
import '../data/repositories/facility_repository_impl.dart';
import '../data/repositories/schedule_repository_impl.dart';
import '../data/repositories/scrape_log_repository_impl.dart';
import '../data/repositories/settings_repository_impl.dart';
import '../data/scraper/ottawa_scraper.dart';
import '../data/services/location_service.dart';
import '../data/services/map_tile_cache_service.dart';
import '../data/services/navigation_service.dart';
import '../data/services/notification_service.dart';
import '../data/services/schedule_validation_service.dart';
import '../data/services/sync_service.dart';
import '../domain/repositories/repositories.dart';
import '../domain/usecases/swim_usecases.dart';

final getIt = GetIt.instance;

Future<void> configureDependencies() async {
  getIt.registerSingleton<AppDatabase>(AppDatabase.instance);

  getIt.registerLazySingleton<FacilityRepository>(
    () => FacilityRepositoryImpl(getIt()),
  );
  getIt.registerLazySingleton<ScheduleRepository>(
    () => ScheduleRepositoryImpl(getIt()),
  );
  getIt.registerLazySingleton<ScrapeLogRepository>(
    () => ScrapeLogRepositoryImpl(getIt()),
  );
  getIt.registerLazySingleton<SettingsRepository>(
    () => SettingsRepositoryImpl(getIt()),
  );

  getIt.registerLazySingleton<OttawaScraper>(
    () => OttawaScraper(
      facilityRepo: getIt(),
      scheduleRepo: getIt(),
      scrapeLogRepo: getIt(),
    ),
  );
  getIt.registerLazySingleton<SyncService>(
    () => SyncService(scraper: getIt(), settingsRepo: getIt()),
  );
  getIt.registerLazySingleton<LocationService>(() => LocationService());
  getIt.registerLazySingleton<MapTileCacheService>(() => MapTileCacheService());
  getIt.registerLazySingleton<NavigationService>(
    () => NavigationService(getIt()),
  );
  getIt.registerLazySingleton<NotificationService>(
    () => NotificationService(getIt()),
  );

  getIt.registerLazySingleton(() => SearchSchedulesUseCase(getIt()));
  getIt.registerLazySingleton(() => GetNearestSwimUseCase(getIt(), getIt()));
  getIt.registerLazySingleton(() => FacilityPinStatusUseCase(getIt()));
  getIt.registerLazySingleton(
    () => ScheduleValidationService(getIt(), getIt()),
  );
}
