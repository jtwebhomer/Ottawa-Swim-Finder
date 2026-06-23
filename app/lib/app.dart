import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'di/injection.dart';
import 'presentation/providers/app_state.dart';
import 'presentation/screens/calendar_screen.dart';
import 'presentation/screens/diagnostics_screen.dart';
import 'presentation/screens/find_swim_screen.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/map_screen.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/screens/saved_screen.dart';
import 'presentation/screens/settings_screen.dart';
import 'data/services/app_version_service.dart';
import 'data/services/connectivity_service.dart';
import 'data/services/location_service.dart';
import 'data/services/saved_swim_reminder_service.dart';
import 'data/services/schedule_validation_service.dart';
import 'data/services/swim_query_service.dart';
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
          )..initialize().catchError((Object error, StackTrace stackTrace) {
              // Logged in main.dart FlutterError handler / app logger.
            }),
        ),
      ],
      child: MaterialApp(
        title: 'Ottawa Swim Finder',
        theme: AppTheme.light(),
        home: const AppBootstrap(),
        routes: {
          '/diagnostics': (_) => const DiagnosticsScreen(),
        },
      ),
    );
  }
}

class AppBootstrap extends StatelessWidget {
  const AppBootstrap({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.needsOnboarding) {
      return const OnboardingScreen();
    }
    return const MainShell();
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
    CalendarScreen(),
    MapScreen(),
    SavedScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Find Swim'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Calendar'),
          NavigationDestination(icon: Icon(Icons.map), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.bookmark), label: 'Saved'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
