import '../entities/facility.dart';
import '../entities/schedule_entry.dart';
import '../entities/scrape_log.dart';

abstract class FacilityRepository {
  Future<List<Facility>> getAllFacilities({bool favoritesFirst = false});
  Future<Facility?> getFacilityById(String id);
  Future<void> upsertFacility(Facility facility);
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
  });
  Future<void> upsertSchedules(String facilityId, List<ScheduleEntry> entries);
  Future<void> deleteSchedulesForFacility(String facilityId);
  Future<int> countSchedulesForFacility(String facilityId);
  Future<int> countAllSchedules();
  Future<int> countSchedulesForDate(String date);
}

abstract class ScrapeLogRepository {
  Future<void> insertLog(ScrapeLog log);
  Future<List<ScrapeLog>> getRecentLogs({int limit = 50});
  Future<List<ScrapeLog>> getErrors({int limit = 20});
}

abstract class SettingsRepository {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<bool> getBool(String key, {bool defaultValue = false});
  Future<void> setBool(String key, bool value);
  Future<int> getLastSyncAt();
  Future<void> setLastSyncAt(int timestamp);
}
