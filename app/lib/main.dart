import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'di/injection.dart';
import 'data/services/map_tile_cache_service.dart';
import 'data/services/notification_service.dart';
import 'data/services/sync_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    await configureDependencies();
    final syncService = getIt<SyncService>();
    await syncService.syncIfNeeded(force: true);
    return true;
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  await getIt<MapTileCacheService>().initialize();
  await getIt<NotificationService>().initialize();

  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    AppConstants.syncTaskName,
    AppConstants.syncTaskName,
    frequency: const Duration(hours: 6),
    constraints: Constraints(networkType: NetworkType.connected),
  );

  runApp(const OttawaSwimFinderApp());
}
