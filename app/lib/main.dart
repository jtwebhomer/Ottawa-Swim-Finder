import 'dart:async';

import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/logging/app_logger.dart';
import 'di/injection.dart';
import 'data/services/map_tile_cache_service.dart';
import 'data/services/notification_service.dart';
import 'data/services/sync_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Toronto'));
    await configureDependencies();
    final syncService = getIt<SyncService>();
    await syncService.syncIfNeeded(force: true);
    return true;
  });
}

Future<void> _initWorkmanager() async {
  await Workmanager().initialize(callbackDispatcher);
  await Workmanager().registerPeriodicTask(
    AppConstants.syncTaskName,
    AppConstants.syncTaskName,
    frequency: const Duration(hours: 8),
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('America/Toronto'));

  FlutterError.onError = (details) {
    appLogger.e(
      'Flutter framework error',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  await configureDependencies();

  try {
    await getIt<MapTileCacheService>().initialize();
  } catch (error, stackTrace) {
    appLogger.e(
      'Map tile cache init failed',
      error: error,
      stackTrace: stackTrace,
    );
  }

  try {
    await getIt<NotificationService>().initialize();
  } catch (error, stackTrace) {
    appLogger.e(
      'Notification init failed',
      error: error,
      stackTrace: stackTrace,
    );
  }

  runApp(const OttawaSwimFinderApp());

  unawaited(() async {
    try {
      await _initWorkmanager();
    } catch (error, stackTrace) {
      appLogger.e(
        'Workmanager init failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }());
}
