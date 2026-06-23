import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'di/injection.dart';
import 'presentation/providers/app_state.dart';
import 'presentation/screens/debug_screen.dart';
import 'presentation/screens/favorites_screen.dart';
import 'presentation/screens/find_swim_screen.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/screens/map_screen.dart';
import 'presentation/screens/search_screen.dart';
import 'presentation/screens/settings_screen.dart';
import 'presentation/screens/todays_swims_screen.dart';

class OttawaSwimFinderApp extends StatelessWidget {
  const OttawaSwimFinderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppState(
            facilityRepo: getIt(),
            scheduleRepo: getIt(),
            scrapeLogRepo: getIt(),
            settingsRepo: getIt(),
            syncService: getIt(),
            locationService: getIt(),
            searchUseCase: getIt(),
            nearestUseCase: getIt(),
            pinStatusUseCase: getIt(),
            validationService: getIt(),
          )..initialize(),
        ),
      ],
      child: MaterialApp(
        title: 'Ottawa Swim Finder',
        theme: AppTheme.light(),
        home: const MainShell(),
        routes: {
          '/debug': (_) => const DebugScreen(),
          '/find-swim': (_) => const FindSwimScreen(),
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
    MapScreen(),
    SearchScreen(),
    TodaysSwimsScreen(),
    FavoritesScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          if (i == 3) {
            context.read<AppState>().clearSearchResults();
          }
          setState(() => _index = i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.map), label: 'Map'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(icon: Icon(Icons.today), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.favorite), label: 'Favs'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
