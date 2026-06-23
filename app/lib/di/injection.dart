import 'package:get_it/get_it.dart';

import '../data/database/app_database.dart';
import '../data/repositories/facility_repository_impl.dart';
import '../data/repositories/schedule_repository_impl.dart';
import '../data/repositories/scrape_log_repository_impl.dart';
import '../data/repositories/sync_log_repository_impl.dart';
import '../data/repositories/saved_swim_repository_impl.dart';
import '../data/repositories/settings_repository_impl.dart';
import '../data/services/facility_discovery_service.dart';
import '../data/services/facility_inclusion_audit_service.dart';
import '../data/services/fetch/tiered_facility_page_fetcher.dart';
import '../data/scraper/ottawa_scraper.dart';
import '../data/services/app_version_service.dart';
import '../data/services/calendar_export_service.dart';
import '../data/services/connectivity_service.dart';
import '../data/services/location_service.dart';
import '../data/services/map_tile_cache_service.dart';
import '../data/services/navigation_service.dart';
import '../data/services/notification_service.dart';
import '../data/services/parser_health_service.dart';
import '../data/services/qa_checklist_service.dart';
import '../data/services/saved_swim_reminder_service.dart';
import '../data/services/schedule_validation_service.dart';
import '../data/services/swim_query_service.dart';
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
  getIt.registerLazySingleton<SyncLogRepository>(
    () => SyncLogRepositoryImpl(getIt()),
  );
  getIt.registerLazySingleton<SettingsRepository>(
    () => SettingsRepositoryImpl(getIt()),
  );
  getIt.registerLazySingleton<SavedSwimRepository>(
    () => SavedSwimRepositoryImpl(getIt()),
  );

  getIt.registerLazySingleton<AppVersionService>(() => AppVersionService());
  getIt.registerLazySingleton<ConnectivityService>(() => ConnectivityService());
  getIt.registerLazySingleton<SwimQueryService>(
    () => SwimQueryService(getIt()),
  );
  getIt.registerLazySingleton<ParserHealthService>(
    () => ParserHealthService(getIt()),
  );
  getIt.registerLazySingleton<QaChecklistService>(
    () => QaChecklistService(getIt()),
  );
  getIt.registerLazySingleton<CalendarExportService>(
    () => CalendarExportService(),
  );

  getIt.registerLazySingleton<TieredFacilityPageFetcher>(
    () => TieredFacilityPageFetcher(),
  );

  getIt.registerLazySingleton<FacilityDiscoveryService>(
    () => FacilityDiscoveryService(fetcher: getIt()),
  );

  getIt.registerLazySingleton<FacilityInclusionAuditService>(
    () => FacilityInclusionAuditService(
      facilityRepo: getIt(),
      scheduleRepo: getIt(),
      discoveryService: getIt(),
    ),
  );

  getIt.registerLazySingleton<OttawaScraper>(
    () => OttawaScraper(
      facilityRepo: getIt(),
      scheduleRepo: getIt(),
      scrapeLogRepo: getIt(),
      syncLogRepo: getIt(),
      tieredFetcher: getIt(),
      discoveryService: getIt(),
    ),
  );
  getIt.registerLazySingleton<SyncService>(
    () => SyncService(
      scraper: getIt(),
      settingsRepo: getIt(),
      versionService: getIt(),
      scheduleRepo: getIt(),
      syncLogRepo: getIt(),
      parserHealthService: getIt(),
    ),
  );
  getIt.registerLazySingleton<LocationService>(() => LocationService());
  getIt.registerLazySingleton<MapTileCacheService>(() => MapTileCacheService());
  getIt.registerLazySingleton<NavigationService>(
    () => NavigationService(getIt()),
  );
  getIt.registerLazySingleton<NotificationService>(
    () => NotificationService(getIt()),
  );
  getIt.registerLazySingleton<SavedSwimReminderService>(
    () => SavedSwimReminderService(getIt<NotificationService>().plugin),
  );

  getIt.registerLazySingleton(() => SearchSchedulesUseCase(getIt()));
  getIt.registerLazySingleton(() => GetNearestSwimUseCase(getIt(), getIt()));
  getIt.registerLazySingleton(() => FacilityPinStatusUseCase(getIt()));
  getIt.registerLazySingleton(
    () => ScheduleValidationService(
      getIt(),
      getIt(),
      inclusionAuditService: getIt(),
    ),
  );
}
