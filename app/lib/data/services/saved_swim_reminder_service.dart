import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/entities/saved_swim.dart';
import '../../domain/entities/schedule_entry.dart';
import 'swim_query_service.dart';

/// Schedules, updates, and cancels saved-swim reminder notifications.
class SavedSwimReminderService {
  SavedSwimReminderService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const _channelId = 'saved_swim_reminders';
  static const _channelName = 'Saved Swim Reminders';

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      );

  int notificationIdFor(SavedSwim swim, {String? occurrenceDate}) {
    final key = '${swim.id}_${occurrenceDate ?? swim.date}_${swim.startTime}';
    return key.hashCode.abs() % 2147483647;
  }

  Future<void> scheduleForSession(
    SavedSwim swim, {
    String? occurrenceDate,
    String? facilityName,
  }) async {
    if (swim.reminderMinutes == null || swim.reminderMinutes! <= 0) return;

    final date = occurrenceDate ?? swim.date;
    if (date.isEmpty) return;

    final start = _sessionStart(date, swim.startTime);
    final remindAt = start.subtract(Duration(minutes: swim.reminderMinutes!));
    if (remindAt.isBefore(DateTime.now())) return;

    final id = notificationIdFor(swim, occurrenceDate: date);
    final title = SwimCategories.displayName(
      category: swim.category,
      rawName: swim.rawCategory,
    );
    final name = facilityName ?? swim.facilityName ?? swim.facilityId;

    try {
      await _plugin.zonedSchedule(
        id,
        'Swim reminder — $title',
        '$name at ${swim.startTime} (${ReminderOptions.labelFor(swim.reminderMinutes!)})',
        tz.TZDateTime.from(remindAt, tz.local),
        _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      appLogger.i('[reminder] scheduled id=$id at $remindAt');
    } catch (e, st) {
      appLogger.e('Failed to schedule reminder', error: e, stackTrace: st);
    }
  }

  Future<void> scheduleForEntry(
    ScheduleEntry entry, {
    required int savedId,
    int? reminderMinutes,
  }) async {
    if (reminderMinutes == null || entry.date == null) return;
    await scheduleForSession(
      SavedSwim(
        id: savedId,
        facilityId: entry.facilityId,
        category: entry.category,
        rawCategory: entry.rawCategory,
        date: entry.date!,
        startTime: entry.startTime,
        endTime: entry.endTime,
        reminderMinutes: reminderMinutes,
        facilityName: entry.facilityName,
      ),
    );
  }

  Future<void> cancelForSwim(SavedSwim swim) async {
    await _plugin.cancel(notificationIdFor(swim));
    // Cancel a few upcoming occurrence ids for recurring patterns.
    for (var i = 0; i < 8; i++) {
      final d = DateTime.now().add(Duration(days: i * 7));
      final date = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      await _plugin.cancel(notificationIdFor(swim, occurrenceDate: date));
    }
  }

  Future<void> cancelId(int notificationId) async {
    await _plugin.cancel(notificationId);
  }

  Future<void> rescheduleAll(List<SavedSwim> swims) async {
    for (final swim in swims) {
      await cancelForSwim(swim);
      if (swim.isRecurring) {
        for (final occ in swim.upcomingOccurrences.take(4)) {
          await scheduleForSession(swim, occurrenceDate: occ.date);
        }
      } else {
        await scheduleForSession(swim);
      }
    }
  }

  DateTime _sessionStart(String date, String time) {
    final parts = date.split('-');
    final tp = time.split(':');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
      int.parse(tp[0]),
      int.parse(tp[1]),
    );
  }
}
