import 'package:flutter/foundation.dart';

import '../../core/logging/app_logger.dart';
import '../../core/utils/ottawa_time.dart';
import '../../data/services/location_service.dart';
import '../../data/services/schedule_trace_logger.dart';
import '../../data/services/schedule_validation_service.dart';
import '../../data/services/sync_health_service.dart';
import '../../data/services/sync_service.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/entities/scrape_log.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/usecases/swim_usecases.dart';

class AppState extends ChangeNotifier {
  AppState({
    required FacilityRepository facilityRepo,
    required ScheduleRepository scheduleRepo,
    required ScrapeLogRepository scrapeLogRepo,
    required SettingsRepository settingsRepo,
    required SyncService syncService,
    required LocationService locationService,
    required SearchSchedulesUseCase searchUseCase,
    required GetNearestSwimUseCase nearestUseCase,
    required FacilityPinStatusUseCase pinStatusUseCase,
    required ScheduleValidationService validationService,
  })  : _facilityRepo = facilityRepo,
        _scheduleRepo = scheduleRepo,
        _scrapeLogRepo = scrapeLogRepo,
        _settingsRepo = settingsRepo,
        _syncService = syncService,
        _locationService = locationService,
        _searchUseCase = searchUseCase,
        _nearestUseCase = nearestUseCase,
        _pinStatusUseCase = pinStatusUseCase,
        _validationService = validationService;

  final FacilityRepository _facilityRepo;
  final ScheduleRepository _scheduleRepo;
  final ScrapeLogRepository _scrapeLogRepo;
  final SettingsRepository _settingsRepo;
  final SyncService _syncService;
  final LocationService _locationService;
  final SearchSchedulesUseCase _searchUseCase;
  final GetNearestSwimUseCase _nearestUseCase;
  final FacilityPinStatusUseCase _pinStatusUseCase;
  final ScheduleValidationService _validationService;
  final _traceLogger = ScheduleTraceLogger();

  bool isLoading = true;
  bool isSyncing = false;
  String? syncMessage;
  List<Facility> facilities = [];
  List<ScheduleEntry> searchResults = [];
  List<ScheduleEntry> activeSwims = [];
  List<ScheduleEntry> timeline = [];
  List<ScrapeLog> scrapeLogs = [];
  Map<String, PinStatus> pinStatuses = {};
  Map<String, ScheduleEntry?> nearestHighlights = {};
  SyncHealthSnapshot? syncHealth;
  List<ScheduleValidationWarning> validationWarnings = [];
  List<RawNameAuditEntry> rawNameAudit = [];
  double? userLat;
  double? userLng;

  /// Today's swims for the Today tab — always from timeline, never search cache.
  List<ScheduleEntry> get todaysSwims => timeline;

  Future<void> initialize() async {
    isLoading = true;
    notifyListeners();

    // Load cached DB data first so UI is never blank while sync runs.
    await refreshAll();
    isLoading = false;
    notifyListeners();

    final syncResult = await _syncService.syncIfNeeded();
    if (syncResult.updated > 0 || syncResult.errors > 0) {
      syncMessage =
          'Sync: ${syncResult.updated} updated, ${syncResult.skipped} skipped, '
          '${syncResult.errors} errors';
    }
    await refreshAll();
  }

  Future<void> refreshAll({bool preserveCachedSwimsOnEmpty = true}) async {
    final today = OttawaTime.todayDate();
    final newFacilities = await _facilityRepo.getAllFacilities(favoritesFirst: true);
    final newActive = await _scheduleRepo.getActiveNow();
    final newTimeline = await _scheduleRepo.getTimelineForDate(today);
    final newPinStatuses = await _pinStatusUseCase.getPinStatuses(newFacilities);
    final newLogs = await _scrapeLogRepo.getRecentLogs();
    final health = await _syncService.healthSnapshot();
    final dbTodayCount = await _scheduleRepo.countSchedulesForDate(today);

    facilities = newFacilities;
    pinStatuses = newPinStatuses;
    scrapeLogs = newLogs;
    syncHealth = health;
    validationWarnings = await _validationService.runValidationChecks();
    rawNameAudit = await _validationService.auditRawNames();

    activeSwims = _mergeScheduleList(
      previous: activeSwims,
      incoming: newActive,
      preserveOnEmpty: preserveCachedSwimsOnEmpty,
      label: 'activeSwims',
      dbCount: dbTodayCount,
    );

    timeline = _mergeScheduleList(
      previous: timeline,
      incoming: newTimeline,
      preserveOnEmpty: preserveCachedSwimsOnEmpty,
      label: 'timeline',
      dbCount: dbTodayCount,
    );

    _traceLogger.logUiDataset(
      today: today,
      timelineCount: timeline.length,
      activeCount: activeSwims.length,
      facilitiesWithToday: timeline
          .where((s) => OttawaTime.isRemainingToday(
                end: s.endTime,
                time: OttawaTime.nowTime(),
              ))
          .map((s) => s.facilityId)
          .toSet()
          .length,
    );

    final position = await _locationService.getCurrentPosition();
    if (position != null) {
      userLat = position.latitude;
      userLng = position.longitude;
      nearestHighlights = await _nearestUseCase.nearestHighlights(
        lat: userLat!,
        lng: userLng!,
      );
    }

    notifyListeners();
  }

  List<ScheduleEntry> _mergeScheduleList({
    required List<ScheduleEntry> previous,
    required List<ScheduleEntry> incoming,
    required bool preserveOnEmpty,
    required String label,
    required int dbCount,
  }) {
    if (incoming.isNotEmpty) return incoming;
    if (!preserveOnEmpty || previous.isEmpty) return incoming;
    if (dbCount > 0) {
      appLogger.w(
        '[app-state] Preserving cached $label (${previous.length}) — '
        'DB has $dbCount rows for today but query returned 0',
      );
      return previous;
    }
    return incoming;
  }

  void clearSearchResults() {
    if (searchResults.isEmpty) return;
    searchResults = [];
    notifyListeners();
  }

  Future<void> manualSync() async {
    isSyncing = true;
    syncMessage = null;
    notifyListeners();

    final result = await _syncService.forceSync();
    syncMessage =
        '${result.statusLabel}: ${result.updated} updated, ${result.skipped} skipped, '
        '${result.errors} errors, ${result.rejected} rejected, '
        'DB ${result.scheduleCountBefore}→${result.scheduleCountAfter}';
    await refreshAll();

    isSyncing = false;
    notifyListeners();
  }

  Future<void> search({
    List<String>? categories,
    String? facilityId,
    DateTime? date,
    String? startAfter,
    String? endBefore,
    double? maxDistanceKm,
    QuickFilter? quickFilter,
  }) async {
    var searchDate = date;
    var searchStart = startAfter;
    var searchEnd = endBefore;

    if (quickFilter != null) {
      final now = DateTime.now();
      searchDate = DateTime(now.year, now.month, now.day);
      switch (quickFilter) {
        case QuickFilter.swimmingNow:
          searchResults = await _scheduleRepo.getActiveNow();
          notifyListeners();
          return;
        case QuickFilter.withinOneHour:
          searchStart = OttawaTime.nowTime();
          searchEnd = OttawaTime.formatTime(
            DateTime.now().add(const Duration(hours: 1)),
          );
        case QuickFilter.tonight:
          searchStart = '17:00';
          searchEnd = '23:59';
        case QuickFilter.tomorrow:
          searchDate = now.add(const Duration(days: 1));
        case QuickFilter.thisWeekend:
          final daysUntilSaturday = (DateTime.saturday - now.weekday + 7) % 7;
          searchDate = now.add(Duration(days: daysUntilSaturday));
      }
    }

    searchResults = await _searchUseCase(
      categories: categories,
      facilityId: facilityId,
      date: searchDate != null ? OttawaTime.formatDate(searchDate) : null,
      startAfter: searchStart,
      endBefore: searchEnd,
      maxDistanceKm: maxDistanceKm,
      userLat: userLat,
      userLng: userLng,
      favoritesFirst: true,
    );
    notifyListeners();
  }

  Future<void> loadTimeline(DateTime date) async {
    timeline = await _scheduleRepo.getTimelineForDate(OttawaTime.formatDate(date));
    notifyListeners();
  }

  Future<void> toggleFavorite(Facility facility) async {
    await _facilityRepo.toggleFavorite(facility.id, !facility.isFavorite);
    await refreshAll();
  }

  Future<bool> getNotificationSetting(String key) =>
      _settingsRepo.getBool(key);

  Future<List<ScheduleEntry>> findSwimsActiveAt(String time) {
    return _scheduleRepo.findSwimsActiveAt(
      date: OttawaTime.todayDate(),
      time: time,
      userLat: userLat,
      userLng: userLng,
    );
  }

  Future<List<ScheduleEntry>> findSwimsAfter(String time) {
    return _scheduleRepo.findSwimsAfter(
      date: OttawaTime.todayDate(),
      time: time,
      userLat: userLat,
      userLng: userLng,
    );
  }

  Future<void> setNotificationSetting(String key, bool value) async {
    await _settingsRepo.setBool(key, value);
    notifyListeners();
  }
}

enum QuickFilter {
  swimmingNow,
  withinOneHour,
  tonight,
  tomorrow,
  thisWeekend,
}
