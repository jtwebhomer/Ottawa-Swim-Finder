import '../entities/habit_event.dart';
import '../entities/facility_interaction.dart';
import '../entities/facility_type.dart';
import '../entities/facility.dart';
import '../entities/saved_swim.dart';
import '../entities/schedule_entry.dart';
import '../entities/scrape_log.dart';
import '../entities/sync_log.dart';
import '../entities/sync_status.dart';

abstract class FacilityRepository {
  Future<List<Facility>> getAllFacilities({
    bool favoritesFirst = false,
    FacilityType? facilityType,
    FacilityScheduleMode? scheduleMode,
  });
  Future<Facility?> getFacilityById(String id);
  Future<void> upsertFacility(Facility facility);
  Future<void> updateSyncMetadata({
    required String facilityId,
    required FacilitySyncStatus syncStatus,
    int? lastSuccessfulSyncAt,
    String? contentHash,
    int? lastUpdated,
  });
  Future<void> toggleFavorite(String facilityId, bool isFavorite);
  Future<List<Facility>> getFavorites();
}

abstract class ScheduleRepository {
  Future<List<ScheduleEntry>> searchSchedules({
    List<String>? categories,
    String? facilityId,
    String? date,
    String? startAfter,
    String? endBefore,
    double? maxDistanceKm,
    double? userLat,
    double? userLng,
    bool favoritesFirst = false,
  });

  Future<List<ScheduleEntry>> getSchedulesForFacility(
    String facilityId, {
    String? date,
  });

  Future<List<ScheduleEntry>> getActiveNow();
  Future<List<ScheduleEntry>> getTimelineForDate(String date, {String? facilityId});

  /// Sessions active at an exact time (start <= time < end).
  Future<List<ScheduleEntry>> findSwimsActiveAt({
    required String date,
    required String time,
    double? userLat,
    double? userLng,
  });

  /// Earliest session starting at or after [time] on [date].
  Future<List<ScheduleEntry>> findSwimsAfter({
    required String date,
    required String time,
    double? userLat,
    double? userLng,
    int limit = 50,
    List<String>? categories,
    String? facilityId,
    double? maxDistanceKm,
  });

  /// Upcoming swims from [fromDate]/[fromTime] through [toDate], sorted soonest first.
  Future<List<ScheduleEntry>> getUpcomingSwims({
    String? fromDate,
    String? fromTime,
    String? toDate,
    int limit = 200,
    List<String>? categories,
    String? facilityId,
    double? userLat,
    double? userLng,
    double? maxDistanceKm,
  });

  /// Distinct dates with at least one swim in [startDate, endDate] (inclusive).
  Future<List<String>> getDatesWithSwims({
    required String startDate,
    required String endDate,
    List<String>? categories,
  });

  Future<int> countFutureSessions(String fromDate);

  Future<int> countFutureSessionsForFacility(String facilityId, String fromDate);

  Future<List<String>> getUnknownRawCategories();

  /// Next swims at or after [date]/[time], including future days.
  Future<List<ScheduleEntry>> findNextSwimsAfter({
    required String date,
    required String time,
    int limit = 50,
    List<String>? categories,
    String? facilityId,
    double? userLat,
    double? userLng,
    double? maxDistanceKm,
  });
  Future<void> upsertSchedules(String facilityId, List<ScheduleEntry> entries);
  Future<void> deleteSchedulesForFacility(String facilityId);

  /// Atomically replaces all schedules for a facility (delete + insert in one transaction).
  Future<void> replaceSchedulesForFacility(
    String facilityId,
    List<ScheduleEntry> entries,
  );
  Future<int> countSchedulesForFacility(String facilityId);
  Future<int> countSchedulesForFacilityOnDate(String facilityId, String date);
  Future<int> countAllSchedules();
  Future<int> countSchedulesForDate(String date);

  /// Date → swim count for calendar heatmap.
  Future<Map<String, int>> getSwimCountsByDate({
    required String startDate,
    required String endDate,
  });

  /// Primary category per date for calendar color hints.
  Future<Map<String, String>> getDominantCategoryByDate({
    required String startDate,
    required String endDate,
  });
}

abstract class ScrapeLogRepository {
  Future<void> insertLog(ScrapeLog log);
  Future<List<ScrapeLog>> getRecentLogs({int limit = 50});
  Future<List<ScrapeLog>> getErrors({int limit = 20});
}

abstract class SyncLogRepository {
  Future<int> insertLog(SyncLogEntry log);
  Future<List<SyncLogEntry>> getRecentLogs({int limit = 20});
  Future<SyncLogEntry?> getLastFullyCleanSync();
}

abstract class SettingsRepository {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<bool> getBool(String key, {bool defaultValue = false});
  Future<void> setBool(String key, bool value);
  Future<int> getLastSyncAt();
  Future<void> setLastSyncAt(int timestamp);
  Future<int> getLastSyncAttemptAt();
  Future<void> setLastSyncAttemptAt(int timestamp);
  Future<String?> getLastSyncStatus();
  Future<void> setLastSyncStatus(String status);
  Future<bool> isOnboardingComplete();
  Future<void> setOnboardingComplete(bool complete);
  Future<String?> getLastSyncedAppVersion();
  Future<void> setLastSyncedAppVersion(String version);
}

abstract class FacilityInteractionRepository {
  Future<FacilityInteractionMetrics> getMetrics(String facilityId);
  Future<Map<String, FacilityInteractionMetrics>> getAllMetrics();
  Future<void> incrementView(String facilityId);
  Future<void> incrementSwimDetailClick(String facilityId);
  Future<void> incrementSaved(String facilityId);
  Future<void> decrementSaved(String facilityId);
  Future<void> incrementImpression(String facilityId);
  Future<void> incrementIgnore(String facilityId);
}

abstract class HabitEventRepository {
  Future<void> insertEvent(HabitEvent event);
  Future<List<HabitEvent>> eventsSince(int sinceMs);
  Future<int> countEventsSince(int sinceMs);
  Future<void> pruneOlderThan(int beforeMs);
}

abstract class SavedSwimRepository {
  Future<List<SavedSwim>> getAll({bool upcomingOnly = false});
  Future<int> saveSession(ScheduleEntry entry, {int? reminderMinutes});
  Future<int> saveRecurringPattern({
    required String facilityId,
    required String category,
    String? rawCategory,
    required int dayOfWeek,
    required String startTime,
    required String endTime,
    int? reminderMinutes,
  });
  Future<void> updateReminder(int id, int? reminderMinutes);
  Future<void> remove(int id);
  Future<bool> isSaved(ScheduleEntry entry);
  Future<SavedSwim?> getById(int id);
}
