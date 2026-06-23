import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../domain/entities/schedule_entry.dart';
import '../../domain/repositories/repositories.dart';

class NotificationService {
  NotificationService(this._settingsRepo);

  final SettingsRepository _settingsRepo;
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  FlutterLocalNotificationsPlugin get plugin => _plugin;

  Future<void> initialize() async {
    if (_initialized) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
  }

  Future<void> notifyUpcomingFavorite(ScheduleEntry entry) async {
    final enabled = await _settingsRepo.getBool('notify_favorites');
    if (!enabled) return;

    await _plugin.show(
      entry.id ?? entry.hashCode,
      'Favorite pool swim soon',
      '${entry.facilityName}: ${entry.startTime} – ${entry.endTime}',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'favorites',
          'Favorite Pool Swims',
          importance: Importance.defaultImportance,
        ),
      ),
    );
  }

  Future<void> notifyNearbySwim(ScheduleEntry entry, double distanceKm) async {
    final enabled = await _settingsRepo.getBool('notify_nearby');
    if (!enabled) return;

    await _plugin.show(
      entry.hashCode,
      'Nearby swim starting soon',
      '${entry.facilityName} (${distanceKm.toStringAsFixed(1)} km)',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'nearby',
          'Nearby Swims',
          importance: Importance.defaultImportance,
        ),
      ),
    );
  }

  Future<void> scheduleDailyReminder() async {
    final enabled = await _settingsRepo.getBool('notify_daily_reminder');
    if (!enabled) return;

    await _plugin.show(
      9999,
      'Ottawa Swim Finder',
      'Check today\'s swim schedules across the city',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily',
          'Daily Reminders',
          importance: Importance.low,
        ),
      ),
    );
  }
}
