import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'di/injection.dart';
import 'presentation/providers/app_state.dart';
import 'presentation/screens/diagnostics_screen.dart';
import 'presentation/screens/find_swim_screen.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/map_screen.dart';
import 'presentation/screens/saved_screen.dart';
import 'presentation/screens/settings_screen.dart';
import 'presentation/widgets/welcome_bottom_sheet.dart';
import 'data/services/facility_interaction_service.dart';
import 'data/services/app_version_service.dart';
import 'data/services/connectivity_service.dart';
import 'data/services/location_service.dart';
import 'data/services/saved_swim_reminder_service.dart';
import 'data/services/schedule_validation_service.dart';
import 'data/services/swim_query_service.dart';
import 'data/services/incremental_sync_engine.dart';
import 'data/services/schedule_trust_resolver.dart';
import 'data/services/seed_database_service.dart';
import 'data/services/sync_freshness_service.dart';
import 'data/services/sync_service.dart';
import 'domain/repositories/repositories.dart';
import 'domain/usecases/swim_usecases.dart';

class OttawaSwimFinderApp extends StatelessWidget {
  const OttawaSwimFinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppState(
            facilityRepo: getIt<FacilityRepository>(),
            scheduleRepo: getIt<ScheduleRepository>(),
            scrapeLogRepo: getIt<ScrapeLogRepository>(),
            settingsRepo: getIt<SettingsRepository>(),
            savedSwimRepo: getIt<SavedSwimRepository>(),
            syncService: getIt<SyncService>(),
            locationService: getIt<LocationService>(),
            searchUseCase: getIt<SearchSchedulesUseCase>(),
            pinStatusUseCase: getIt<FacilityPinStatusUseCase>(),
            validationService: getIt<ScheduleValidationService>(),
            swimQueryService: getIt<SwimQueryService>(),
            versionService: getIt<AppVersionService>(),
            connectivityService: getIt<ConnectivityService>(),
            reminderService: getIt<SavedSwimReminderService>(),
            seedService: getIt<SeedDatabaseService>(),
            incrementalSync: getIt<IncrementalSyncEngine>(),
            freshnessService: getIt<SyncFreshnessService>(),
            interactionService: getIt<FacilityInteractionService>(),
            trustResolver: getIt<ScheduleTrustResolver>(),
          )..initialize().catchError((Object error, StackTrace stackTrace) {
              // Logged in main.dart FlutterError handler / app logger.
            }),
        ),
      ],
      child: MaterialApp(
        title: 'Ottawa Swim Finder',
        theme: AppTheme.light(),
        home: const MainShell(),
        routes: {
          '/diagnostics': (_) => const DiagnosticsScreen(),
        },
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    FindSwimScreen(),
    MapScreen(),
    SavedScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowWelcome());
  }

  void _maybeShowWelcome() {
    final state = context.read<AppState>();
    if (state.shouldShowWelcomeSheet && !state.welcomeSheetScheduled) {
      state.markWelcomeSheetScheduled();
      showWelcomeBottomSheet(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        if (state.isLoading) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  Text(
                    state.onboardingStage,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (state.isSyncing && state.syncProgress != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Facility ${state.syncProgress!.completed} of ${state.syncProgress!.totalFacilities}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return Selector<AppState, bool>(
          selector: (_, s) => s.shouldShowWelcomeSheet,
          builder: (context, shouldShowWelcome, _) {
            if (shouldShowWelcome) {
              final scheduled = context.read<AppState>().welcomeSheetScheduled;
              if (!scheduled) {
                WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowWelcome());
              }
            }

            return Scaffold(
              body: IndexedStack(index: _index, children: _screens),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: const [
                  NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
                  NavigationDestination(icon: Icon(Icons.search), label: 'Find Swim'),
                  NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map'),
                  NavigationDestination(icon: Icon(Icons.bookmark_border), selectedIcon: Icon(Icons.bookmark), label: 'Saved'),
                  NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
