import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/constants/sync_rate_limit_policy.dart';
import '../../core/logging/app_logger.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/ottawa_time.dart';
import '../../data/services/facility_interaction_service.dart';
import '../../data/services/app_version_service.dart';
import '../../data/services/connectivity_service.dart';
import '../../data/services/location_service.dart';
import '../../data/services/saved_swim_reminder_service.dart';
import '../../data/services/schedule_trace_logger.dart';
import '../../data/services/schedule_validation_service.dart';
import '../../data/services/swim_query_service.dart';
import '../../data/services/parser_health_service.dart';
import '../../data/services/sync_health_service.dart';
import '../../data/services/incremental_sync_engine.dart';
import '../../data/services/seed_database_service.dart';
import '../../data/services/schedule_trust_resolver.dart';
import '../../data/services/sync_freshness_service.dart';
import '../../data/services/sync_service.dart';
import '../../domain/entities/sync_freshness.dart';
import '../../domain/entities/sync_result.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/saved_swim.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/entities/scrape_log.dart';
import '../../data/services/facility_browse_helper.dart';
import '../../domain/entities/facility_sync_diagnostic.dart';
import '../../domain/entities/facility_inclusion_trace.dart';
import '../../domain/entities/facility_type.dart';
import '../../domain/entities/sync_progress.dart';
import '../../domain/entities/schedule_trust_status.dart';
import '../../domain/entities/sync_status.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/usecases/swim_usecases.dart';

class AppState extends ChangeNotifier {
  AppState({
    required FacilityRepository facilityRepo,
    required ScheduleRepository scheduleRepo,
    required ScrapeLogRepository scrapeLogRepo,
    required SettingsRepository settingsRepo,
    required SavedSwimRepository savedSwimRepo,
    required SyncService syncService,
    required LocationService locationService,
    required SearchSchedulesUseCase searchUseCase,
    required FacilityPinStatusUseCase pinStatusUseCase,
    required ScheduleValidationService validationService,
    required SwimQueryService swimQueryService,
    required AppVersionService versionService,
    required ConnectivityService connectivityService,
    required SavedSwimReminderService reminderService,
    required SeedDatabaseService seedService,
    required IncrementalSyncEngine incrementalSync,
    required SyncFreshnessService freshnessService,
    required FacilityInteractionService interactionService,
    ScheduleTrustResolver? trustResolver,
  })  : _facilityRepo = facilityRepo,
        _scheduleRepo = scheduleRepo,
        _scrapeLogRepo = scrapeLogRepo,
        _settingsRepo = settingsRepo,
        _savedSwimRepo = savedSwimRepo,
        _syncService = syncService,
        _locationService = locationService,
        _searchUseCase = searchUseCase,
        _pinStatusUseCase = pinStatusUseCase,
        _validationService = validationService,
        _swimQueryService = swimQueryService,
        _versionService = versionService,
        _connectivity = connectivityService,
        _reminderService = reminderService,
        _seedService = seedService,
        _incrementalSync = incrementalSync,
        _freshnessService = freshnessService,
        _interactionService = interactionService,
        _trustResolver = trustResolver ?? ScheduleTrustResolver(settingsRepo: settingsRepo);

  final FacilityRepository _facilityRepo;
  final ScheduleRepository _scheduleRepo;
  final ScrapeLogRepository _scrapeLogRepo;
  final SettingsRepository _settingsRepo;
  final SavedSwimRepository _savedSwimRepo;
  final SyncService _syncService;
  final LocationService _locationService;
  final SearchSchedulesUseCase _searchUseCase;
  final FacilityPinStatusUseCase _pinStatusUseCase;
  final ScheduleValidationService _validationService;
  final SwimQueryService _swimQueryService;
  final AppVersionService _versionService;
  final ConnectivityService _connectivity;
  final SavedSwimReminderService _reminderService;
  final SeedDatabaseService _seedService;
  final IncrementalSyncEngine _incrementalSync;
  final SyncFreshnessService _freshnessService;
  final FacilityInteractionService _interactionService;
  final ScheduleTrustResolver _trustResolver;
  final _traceLogger = ScheduleTraceLogger();

  /// Prevents overlapping background/manual sync runs.
  Future<IncrementalSyncResult>? _syncInFlight;

  /// Supersedes stale in-flight [refreshAll] results when a newer refresh starts.
  int _refreshGeneration = 0;

  DateTime? _lastProgressNotifyAt;

  bool isLoading = true;
  bool isSyncing = false;
  SyncProgress? syncProgress;
  SyncStatus? lastSyncStatus;
  List<String> staleFacilityNames = [];
  List<String> failedFacilityNames = [];
  List<String> blockedFacilityNames = [];
  String? lastSyncRootCause;
  List<FacilitySyncDiagnostic> lastFacilityDiagnostics = [];
  FacilityCatalogAudit? facilityCatalogAudit;
  FacilityType? facilityTypeFilter;
  FacilityScheduleMode? scheduleModeFilter;
  FacilityType? mapFacilityTypeFilter;
  Map<String, int> facilitySessionCounts = {};
  bool backgroundSyncActive = false;
  SyncFreshnessSnapshot? syncFreshness;
  ScheduleTrustSummary? trustSummary;
  bool shouldShowWelcomeSheet = false;
  bool welcomeSheetScheduled = false;
  bool isOnline = true;
  String? syncMessage;
  String? lastSyncEngine;
  String onboardingStage = 'Checking…';
  String appVersion = '—';
  String? lastSyncedAppVersion;
  String? syncAnomalyWarning;
  bool showOnboardingSuccess = false;
  int onboardingFacilityCount = 0;
  int onboardingSessionCount = 0;
  ParserHealthSnapshot? parserHealth;

  int _staleThresholdHours = SyncRateLimitPolicy.defaultStaleThresholdHours;

  List<Facility> facilities = [];
  List<ScheduleEntry> searchResults = [];
  List<ScheduleEntry> activeSwims = [];
  List<ScheduleEntry> homeUpcomingSwims = [];
  HomeSwimSections homeSections = const HomeSwimSections(
    swimmingNow: [],
    startingSoon: [],
    tonight: [],
    tomorrow: [],
  );
  List<ScheduleEntry> calendarSwims = [];
  List<SavedSwim> savedSwims = [];
  List<ScrapeLog> scrapeLogs = [];
  Map<String, PinStatus> pinStatuses = {};
  SyncHealthSnapshot? syncHealth;
  List<ScheduleValidationWarning> validationWarnings = [];
  List<RawNameAuditEntry> rawNameAudit = [];
  List<String> unknownCategories = [];
  List<CategoryInventoryRow> categoryInventory = [];
  int futureSessionCount = 0;
  int totalSessionCount = 0;
  int scrapeErrorCount = 0;
  double? userLat;
  double? userLng;

  String calendarSelectedDate = OttawaTime.todayDate();
  Map<String, int> calendarSwimCounts = {};
  Map<String, String> calendarDominantCategories = {};

  List<ScheduleEntry> get todaysSwims => homeUpcomingSwims;

  Future<void> initialize() async {
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    isOnline = await _connectivity.checkOnline();
    appVersion = await _versionService.fullVersionLabel();
    lastSyncedAppVersion = await _settingsRepo.getLastSyncedAppVersion();
    lastSyncEngine = await _settingsRepo.getString(AppConstants.settingsLastSyncEngine);

    onboardingStage = 'Loading facilities…';
    notifyListeners();

    await _seedService.ensureSeeded();

    final initialSyncDone = await _settingsRepo.getBool(
      AppConstants.settingsInitialApiSyncDone,
    );

    if (isOnline && !initialSyncDone) {
      onboardingStage = 'Downloading swim schedules…';
      isSyncing = true;
      notifyListeners();

      try {
        await _incrementalSync.runManualSync(
          onProgress: _onSyncProgress,
        );
        await _settingsRepo.setBool(AppConstants.settingsInitialApiSyncDone, true);
      } catch (e, st) {
        appLogger.w('[bootstrap] Initial API sync failed', error: e, stackTrace: st);
        onboardingStage = 'Using cached schedules…';
        notifyListeners();
      } finally {
        isSyncing = false;
        syncProgress = null;
      }
    }

    onboardingStage = 'Preparing home…';
    notifyListeners();

    await refreshAll();
    syncFreshness = await _freshnessService.load();
    trustSummary = syncFreshness?.trustSummary;
    onboardingFacilityCount = facilities.length;
    onboardingSessionCount = totalSessionCount;

    if ((trustSummary?.fixture ?? 0) > 0 && (trustSummary?.verified ?? 0) == 0) {
      syncMessage =
          'Using bundled schedule data. Live verification will occur automatically.';
    }

    final welcomeDone = await _settingsRepo.isOnboardingComplete();
    shouldShowWelcomeSheet = !welcomeDone;
    notifyListeners();

    if (!shouldShowWelcomeSheet) {
      await _reminderService.rescheduleAll(savedSwims);
      unawaited(_runBackgroundSync());
    }

    isLoading = false;
    notifyListeners();
  }

  Facility? facilityFor(String facilityId) {
    for (final facility in facilities) {
      if (facility.id == facilityId) return facility;
    }
    return null;
  }

  void markWelcomeSheetScheduled() {
    welcomeSheetScheduled = true;
  }

  Future<void> _runBackgroundSync() async {
    if (_syncInFlight != null) return;

    isOnline = await _connectivity.checkOnline();
    if (!isOnline) {
      notifyListeners();
      return;
    }

    final versionSyncNeeded = await _syncService.needsVersionSync();
    backgroundSyncActive = true;
    isSyncing = true;
    notifyListeners();

    _syncInFlight = _incrementalSync.runBackgroundSync(
      force: versionSyncNeeded,
      userLat: userLat,
      userLng: userLng,
      onProgress: _onSyncProgress,
      onPhaseComplete: (_) async {
        syncFreshness = await _freshnessService.load();
      },
    );

    try {
      final result = await _syncInFlight!;
      _applySyncResult(result.syncResult);
      lastSyncedAppVersion = await _settingsRepo.getLastSyncedAppVersion();
      lastSyncEngine = await _settingsRepo.getString(AppConstants.settingsLastSyncEngine);
      syncFreshness = await _freshnessService.load();
      await refreshAll();
    } finally {
      _syncInFlight = null;
      isSyncing = false;
      backgroundSyncActive = false;
      syncProgress = null;
      notifyListeners();
    }
  }

  void _onSyncProgress(SyncProgress progress) {
    syncProgress = progress;
    final now = DateTime.now();
    if (_lastProgressNotifyAt != null &&
        now.difference(_lastProgressNotifyAt!).inMilliseconds < 250) {
      return;
    }
    _lastProgressNotifyAt = now;
    notifyListeners();
  }

  void _applySyncResult(SyncResult result) {
    lastSyncStatus = result.syncStatus;
    staleFacilityNames = result.staleFacilityNames;
    failedFacilityNames = result.failedFacilityNames;
    blockedFacilityNames = result.blockedFacilityNames;
    lastSyncRootCause = result.rootCauseSummary;
    lastFacilityDiagnostics = result.facilityDiagnostics;

    if (result.isOffline) {
      syncMessage = 'Offline mode — showing cached schedules.';
    } else if (result.antiCorruptionTriggered) {
      syncAnomalyWarning = result.antiCorruptionReason ??
          'Source schedule data appears incomplete. '
          'Using previously verified schedule data.';
    } else if (result.updated > 0 || result.syncStatus == SyncStatus.success) {
      syncAnomalyWarning = null;
    }

    if (result.updated > 0 ||
        result.blocked > 0 ||
        result.parseEmpty > 0 ||
        result.syncStatus == SyncStatus.partialSuccess ||
        result.syncStatus == SyncStatus.failed) {
      syncMessage = switch (result.syncStatus) {
        SyncStatus.success when result.updated > 0 =>
          'Schedules updated.',
        SyncStatus.success =>
          'Schedules are up to date.',
        SyncStatus.partialSuccess =>
          'Some pool schedules are still updating. Your saved swims remain available.',
        SyncStatus.failed when result.isFirstInstallBlocked =>
          'Using bundled schedule data. Live verification will occur automatically.',
        SyncStatus.failed when result.isMostlyBlocked =>
          'Live updates temporarily unavailable. Showing last verified schedules.',
        SyncStatus.failed => 'Could not refresh all schedules. Cached swims remain available.',
      };
    }
  }

  bool isFacilityStale(String facilityId) {
    for (final f in facilities) {
      if (f.id == facilityId) return f.isStale;
    }
    return false;
  }

  int get staleFacilityCount =>
      facilities.where((f) => f.isStale).length;

  List<Facility> get filteredFacilities {
    return facilities.where((f) {
      if (facilityTypeFilter != null && f.facilityType != facilityTypeFilter) {
        return false;
      }
      if (scheduleModeFilter != null && f.scheduleMode != scheduleModeFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Aquatic facilities with coordinates for map rendering.
  List<Facility> get mapVisibleFacilities {
    return facilities.where((f) {
      if (f.latitude == null || f.longitude == null) return false;
      if (!f.isAquatic) return false;
      if (mapFacilityTypeFilter != null &&
          f.facilityType != mapFacilityTypeFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  Map<String, int> get facilityBrowseCounts {
    int countType(FacilityType type) =>
        facilities.where((f) => f.facilityType == type).length;
    return {
      'total': facilities.length,
      'visible': filteredFacilities.length,
      'indoor': facilities
          .where((f) =>
              f.facilityType == FacilityType.indoorPool ||
              f.facilityType == FacilityType.wavePool)
          .length,
      'outdoor': countType(FacilityType.outdoorPool),
      'wave': countType(FacilityType.wavePool),
      'wading': countType(FacilityType.wadingPool),
      'splash': countType(FacilityType.splashPad),
    };
  }

  FacilityBrowseStatus browseStatusFor(Facility facility) {
    final sessions = facilitySessionCounts[facility.id] ?? 0;
    final trust = effectiveTrustFor(facility, sessions);
    return FacilityBrowseHelper.statusFor(
      facility: facility,
      sessionCount: sessions,
      todaySessionCount: sessions,
      trustStatus: trust,
    );
  }

  ScheduleTrustStatus effectiveTrustFor(Facility facility, int sessionCount) {
    return _trustResolver.resolve(
      facility: facility,
      scheduleCount: sessionCount,
      staleThresholdHours: _staleThresholdHours,
      syncBlocked: lastSyncStatus == SyncStatus.failed ||
          lastSyncStatus == SyncStatus.partialSuccess,
    );
  }

  void setMapFacilityTypeFilter(FacilityType? type) {
    mapFacilityTypeFilter = type;
    notifyListeners();
  }

  void setFacilityTypeFilter(FacilityType? type) {
    facilityTypeFilter = type;
    notifyListeners();
  }

  void setScheduleModeFilter(FacilityScheduleMode? mode) {
    scheduleModeFilter = mode;
    notifyListeners();
  }

  Future<void> refreshFacilityAudit() async {
    facilityCatalogAudit = await _validationService.runFacilityInclusionAudit(
      uiFacilities: facilities,
    );
    notifyListeners();
  }

  Future<void> completeWelcome() async {
    await _settingsRepo.setOnboardingComplete(true);
    shouldShowWelcomeSheet = false;
    showOnboardingSuccess = false;
    notifyListeners();
    await _reminderService.rescheduleAll(savedSwims);
    unawaited(_runBackgroundSync());
  }

  @Deprecated('Use completeWelcome')
  Future<void> completeOnboarding() => completeWelcome();

  Future<void> refreshAll({bool preserveCachedSwimsOnEmpty = true}) async {
    final generation = ++_refreshGeneration;
    isOnline = await _connectivity.checkOnline();
    final today = OttawaTime.todayDate();
    final now = OttawaTime.nowTime();
    final newFacilities = await _facilityRepo.getAllFacilities(favoritesFirst: true);
    final newActive = await _scheduleRepo.getActiveNow();
    final sections = await _swimQueryService.homeSections(
      userLat: userLat,
      userLng: userLng,
      facilities: newFacilities,
    );
    final newUpcoming = await _scheduleRepo.getUpcomingSwims(
      fromDate: today,
      fromTime: now,
      limit: 100,
      userLat: userLat,
      userLng: userLng,
    );
    final calendarDate = calendarSelectedDate;
    final newCalendar = await _scheduleRepo.getTimelineForDate(calendarDate);
    final newPinStatuses = await _pinStatusUseCase.getPinStatuses(newFacilities);
    final newLogs = await _scrapeLogRepo.getRecentLogs();
    final health = await _syncService.healthSnapshot();
    final dbTodayCount = await _scheduleRepo.countSchedulesForDate(today);

    facilities = newFacilities;
    final sessionCounts = <String, int>{};
    for (final facility in newFacilities) {
      sessionCounts[facility.id] =
          await _scheduleRepo.countSchedulesForFacility(facility.id);
    }
    facilitySessionCounts = sessionCounts;

    try {
      facilityCatalogAudit =
          await _validationService.runFacilityInclusionAudit(
        uiFacilities: newFacilities,
      );
    } catch (e) {
      appLogger.w('Facility inclusion audit failed', error: e);
    }

    pinStatuses = newPinStatuses;
    scrapeLogs = newLogs;
    syncHealth = health;
    final statusRaw = health.lastSyncStatus;
    if (statusRaw != null) {
      lastSyncStatus = SyncStatus.values.firstWhere(
        (s) => s.label == statusRaw,
        orElse: () => SyncStatus.partialSuccess,
      );
    }
    staleFacilityNames = newFacilities
        .where((f) => f.isStale)
        .map((f) => f.name)
        .toList();
    parserHealth = await _syncService.parserHealthSnapshot();
    savedSwims = await _savedSwimRepo.getAll(upcomingOnly: true);
    unknownCategories = await _scheduleRepo.getUnknownRawCategories();
    categoryInventory = await _scheduleRepo.getCategoryInventory();
    futureSessionCount = await _scheduleRepo.countFutureSessions(today);
    totalSessionCount = await _scheduleRepo.countAllSchedules();
    scrapeErrorCount = (await _scrapeLogRepo.getErrors()).length;
    validationWarnings = await _validationService.runValidationChecks();
    rawNameAudit = await _validationService.auditRawNames();
    homeSections = sections;
    lastSyncedAppVersion =
        health.lastSyncedAppVersion ?? await _settingsRepo.getLastSyncedAppVersion();

    activeSwims = _mergeScheduleList(
      previous: activeSwims,
      incoming: newActive,
      preserveOnEmpty: preserveCachedSwimsOnEmpty,
      label: 'activeSwims',
      dbCount: dbTodayCount,
    );

    homeUpcomingSwims = _mergeScheduleList(
      previous: homeUpcomingSwims,
      incoming: newUpcoming,
      preserveOnEmpty: preserveCachedSwimsOnEmpty,
      label: 'homeUpcomingSwims',
      dbCount: dbTodayCount,
    );

    calendarSwims = newCalendar;

    _traceLogger.logUiDataset(
      today: today,
      timelineCount: homeUpcomingSwims.length,
      activeCount: activeSwims.length,
      facilitiesWithToday: homeUpcomingSwims
          .where((s) => s.date == today)
          .map((s) => s.facilityId)
          .toSet()
          .length,
    );

    final position = await _locationService.getCurrentPosition();
    if (position != null) {
      userLat = position.latitude;
      userLng = position.longitude;
      homeSections = await _swimQueryService.homeSections(
        userLat: userLat,
        userLng: userLng,
        facilities: facilities,
      );
      homeUpcomingSwims = await _scheduleRepo.getUpcomingSwims(
        fromDate: today,
        fromTime: now,
        limit: 100,
        userLat: userLat,
        userLng: userLng,
      );
    }

    syncFreshness = await _freshnessService.load();
    trustSummary = syncFreshness?.trustSummary;
    lastSyncEngine = await _settingsRepo.getString(AppConstants.settingsLastSyncEngine);
    _staleThresholdHours = await _trustResolver.staleThresholdHours();
    if (generation != _refreshGeneration) return;
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

  Future<void> loadCalendarDate(String date) async {
    calendarSelectedDate = date;
    calendarSwims = await _scheduleRepo.getTimelineForDate(date);
    notifyListeners();
  }

  Future<void> loadCalendarMonth(DateTime month) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0);
    final startStr = OttawaTime.formatDate(start);
    final endStr = OttawaTime.formatDate(end);
    calendarSwimCounts = await _scheduleRepo.getSwimCountsByDate(
      startDate: startStr,
      endDate: endStr,
    );
    calendarDominantCategories = await _scheduleRepo.getDominantCategoryByDate(
      startDate: startStr,
      endDate: endStr,
    );
    notifyListeners();
  }

  Future<List<String>> datesWithSwims(DateTime month) async {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0);
    return _scheduleRepo.getDatesWithSwims(
      startDate: OttawaTime.formatDate(start),
      endDate: OttawaTime.formatDate(end),
    );
  }

  Future<FacilitySwimSummary> facilitySwimSummary(String facilityId) =>
      _swimQueryService.facilitySummary(facilityId);

  Future<ScheduleEntry?> nextAvailableSwim() async {
    final today = OttawaTime.todayDate();
    final now = OttawaTime.nowTime();
    final results = await _scheduleRepo.findNextSwimsAfter(
      date: today,
      time: now,
      limit: 1,
      userLat: userLat,
      userLng: userLng,
    );
    return results.isEmpty ? null : results.first;
  }

  void clearSearchResults() {
    if (searchResults.isEmpty) return;
    searchResults = [];
    notifyListeners();
  }

  Future<void> manualSync() async {
    if (_syncInFlight != null) {
      await _syncInFlight;
      return;
    }

    isOnline = await _connectivity.checkOnline();
    if (!isOnline) {
      syncMessage = 'You\'re offline — cached swims are still available.';
      notifyListeners();
      return;
    }

    isSyncing = true;
    syncMessage = null;
    syncProgress = null;
    notifyListeners();

    _syncInFlight = _incrementalSync.runManualSync(
      userLat: userLat,
      userLng: userLng,
      onProgress: _onSyncProgress,
      onPhaseComplete: (_) async {
        syncFreshness = await _freshnessService.load();
      },
    );

    try {
      final result = await _syncInFlight!;
      _applySyncResult(result.syncResult);
      lastSyncedAppVersion = await _settingsRepo.getLastSyncedAppVersion();
      lastSyncEngine = await _settingsRepo.getString(AppConstants.settingsLastSyncEngine);
      syncFreshness = await _freshnessService.load();
      await refreshAll();
    } finally {
      _syncInFlight = null;
      isSyncing = false;
      syncProgress = null;
      notifyListeners();
    }
  }

  Future<void> search({
    List<String>? categories,
    String? facilityId,
    DateTime? date,
    String? startDate,
    String? endDate,
    String? startAfter,
    String? endBefore,
    double? maxDistanceKm,
    QuickFilter? quickFilter,
  }) async {
    var searchDate = date;
    var searchStart = startDate;
    var searchEnd = endDate;
    var searchStartAfter = startAfter;
    var searchEndBefore = endBefore;

    if (quickFilter != null) {
      final now = DateTime.now();
      searchDate = DateTime(now.year, now.month, now.day);
      switch (quickFilter) {
        case QuickFilter.swimmingNow:
          searchResults = await _scheduleRepo.getActiveNow();
          notifyListeners();
          return;
        case QuickFilter.withinOneHour:
          searchStartAfter = OttawaTime.nowTime();
          searchEndBefore = OttawaTime.formatTime(
            DateTime.now().add(const Duration(hours: 1)),
          );
        case QuickFilter.tonight:
          searchStartAfter = '17:00';
          searchEndBefore = '23:59';
        case QuickFilter.tomorrow:
          searchDate = now.add(const Duration(days: 1));
        case QuickFilter.thisWeekend:
          final daysUntilSaturday = (DateTime.saturday - now.weekday + 7) % 7;
          searchDate = now.add(Duration(days: daysUntilSaturday));
      }
    }

    if (searchStart != null && searchEnd != null) {
      searchResults = await _scheduleRepo.getUpcomingSwims(
        fromDate: searchStart,
        fromTime: '00:00',
        toDate: searchEnd,
        categories: categories,
        facilityId: facilityId,
        userLat: userLat,
        userLng: userLng,
        maxDistanceKm: maxDistanceKm,
      );
    } else {
      searchResults = await _searchUseCase(
        categories: categories,
        facilityId: facilityId,
        date: searchDate != null ? OttawaTime.formatDate(searchDate) : null,
        startAfter: searchStartAfter,
        endBefore: searchEndBefore,
        maxDistanceKm: maxDistanceKm,
        userLat: userLat,
        userLng: userLng,
        favoritesFirst: true,
      );
    }
    notifyListeners();
  }

  Future<void> toggleFavorite(Facility facility) async {
    final nextFavorite = !facility.isFavorite;
    await _facilityRepo.toggleFavorite(facility.id, nextFavorite);
    if (nextFavorite) {
      await _interactionService.recordFavorite(facility.id);
    } else {
      await _interactionService.recordUnfavorite(facility.id);
    }
    await refreshAll();
  }

  Future<void> saveSwim(
    ScheduleEntry entry, {
    int? reminderMinutes,
    bool asRecurring = false,
  }) async {
    int savedId;
    if (asRecurring && entry.dayOfWeek != null) {
      savedId = await _savedSwimRepo.saveRecurringPattern(
        facilityId: entry.facilityId,
        category: entry.category,
        rawCategory: entry.rawCategory,
        dayOfWeek: entry.dayOfWeek!,
        startTime: entry.startTime,
        endTime: entry.endTime,
        reminderMinutes: reminderMinutes,
      );
    } else {
      savedId = await _savedSwimRepo.saveSession(
        entry,
        reminderMinutes: reminderMinutes,
      );
    }
    savedSwims = await _savedSwimRepo.getAll(upcomingOnly: true);
    await _interactionService.recordSaveSwim(
      entry.facilityId,
      swimStartTime: entry.startTime,
      swimDate: entry.date,
    );
    final saved = await _savedSwimRepo.getById(savedId);
    if (saved != null) {
      if (saved.isRecurring) {
        for (final occ in saved.upcomingOccurrences.take(4)) {
          await _reminderService.scheduleForSession(
            saved,
            occurrenceDate: occ.date,
            facilityName: saved.facilityName,
          );
        }
      } else {
        await _reminderService.scheduleForSession(
          saved,
          facilityName: saved.facilityName,
        );
      }
    }
    notifyListeners();
  }

  Future<void> updateSavedSwimReminder(int id, int? reminderMinutes) async {
    await _savedSwimRepo.updateReminder(id, reminderMinutes);
    final swim = await _savedSwimRepo.getById(id);
    if (swim != null) {
      await _reminderService.cancelForSwim(swim);
      if (reminderMinutes != null) {
        if (swim.isRecurring) {
          for (final occ in swim.upcomingOccurrences.take(4)) {
            await _reminderService.scheduleForSession(
              swim.copyWith(upcomingOccurrences: swim.upcomingOccurrences),
              occurrenceDate: occ.date,
              facilityName: swim.facilityName,
            );
          }
        } else {
          await _reminderService.scheduleForSession(
            swim,
            facilityName: swim.facilityName,
          );
        }
      }
    }
    savedSwims = await _savedSwimRepo.getAll(upcomingOnly: true);
    notifyListeners();
  }

  Future<void> removeSavedSwim(int id) async {
    final swim = await _savedSwimRepo.getById(id);
    if (swim != null) await _reminderService.cancelForSwim(swim);
    await _savedSwimRepo.remove(id);
    savedSwims = await _savedSwimRepo.getAll(upcomingOnly: true);
    notifyListeners();
  }

  Future<List<ScheduleEntry>> findSwimsActiveAt(
    String time, {
    String? date,
    String? endDate,
    List<String>? categories,
    List<String>? rawCategories,
    String? facilityId,
    double? maxDistanceKm,
  }) async {
    if (endDate != null && endDate != date) {
      final all = await _scheduleRepo.getUpcomingSwims(
        fromDate: date ?? OttawaTime.todayDate(),
        fromTime: '00:00',
        toDate: endDate,
        categories: categories,
        rawCategories: rawCategories,
        facilityId: facilityId,
        userLat: userLat,
        userLng: userLng,
        maxDistanceKm: maxDistanceKm,
      );
      return all
          .where((e) =>
              e.date != null &&
              OttawaTime.isActiveAt(
                start: e.startTime,
                end: e.endTime,
                time: time,
              ))
          .toList();
    }

    var results = await _scheduleRepo.findSwimsActiveAt(
      date: date ?? OttawaTime.todayDate(),
      time: time,
      userLat: userLat,
      userLng: userLng,
    );
    results = _applyClientFilters(
      results,
      categories: categories,
      rawCategories: rawCategories,
      facilityId: facilityId,
      maxDistanceKm: maxDistanceKm,
    );
    return results;
  }

  Future<List<ScheduleEntry>> findSwimsAfter(
    String time, {
    String? date,
    String? endDate,
    List<String>? categories,
    List<String>? rawCategories,
    String? facilityId,
    double? maxDistanceKm,
    bool nextAcrossDays = false,
  }) async {
    final queryDate = date ?? OttawaTime.todayDate();
    if (endDate != null) {
      return _scheduleRepo.getUpcomingSwims(
        fromDate: queryDate,
        fromTime: time,
        toDate: endDate,
        categories: categories,
        rawCategories: rawCategories,
        facilityId: facilityId,
        userLat: userLat,
        userLng: userLng,
        maxDistanceKm: maxDistanceKm,
      );
    }
    if (nextAcrossDays) {
      return _scheduleRepo.findNextSwimsAfter(
        date: queryDate,
        time: time,
        userLat: userLat,
        userLng: userLng,
        categories: categories,
        rawCategories: rawCategories,
        facilityId: facilityId,
        maxDistanceKm: maxDistanceKm,
      );
    }
    return _scheduleRepo.findSwimsAfter(
      date: queryDate,
      time: time,
      userLat: userLat,
      userLng: userLng,
      categories: categories,
      rawCategories: rawCategories,
      facilityId: facilityId,
      maxDistanceKm: maxDistanceKm,
    );
  }

  List<ScheduleEntry> _applyClientFilters(
    List<ScheduleEntry> results, {
    List<String>? categories,
    List<String>? rawCategories,
    String? facilityId,
    double? maxDistanceKm,
  }) {
    if (categories != null && categories.isNotEmpty) {
      final expanded = {
        ...categories,
        if (categories.contains(SwimCategories.generalSwim))
          ...['public_swim', 'open_swim', 'other'],
      };
      results = results.where((e) => expanded.contains(e.category)).toList();
    }
    if (rawCategories != null && rawCategories.isNotEmpty) {
      results = results
          .where(
            (e) =>
                rawCategories.contains(e.rawCategory) ||
                rawCategories.contains(
                  e.rawCategory?.trim().isNotEmpty == true
                      ? e.rawCategory
                      : e.category,
                ),
          )
          .toList();
    }
    if (facilityId != null) {
      results = results.where((e) => e.facilityId == facilityId).toList();
    }
    if (maxDistanceKm != null) {
      results = results
          .where((e) => (e.distanceKm ?? double.infinity) <= maxDistanceKm)
          .toList();
    }
    return results;
  }

  Future<bool> getNotificationSetting(String key) =>
      _settingsRepo.getBool(key);

  Future<void> setNotificationSetting(String key, bool value) async {
    await _settingsRepo.setBool(key, value);
    notifyListeners();
  }

  Future<List<ScheduleEntry>> scheduleForFacilityOnDate(
    String facilityId,
    String date,
  ) =>
      _scheduleRepo.getTimelineForDate(date, facilityId: facilityId);

  Future<List<ScheduleEntry>> upcomingForFacility(String facilityId) async {
    final today = OttawaTime.todayDate();
    final now = OttawaTime.nowTime();
    return _scheduleRepo.getUpcomingSwims(
      fromDate: today,
      fromTime: now,
      facilityId: facilityId,
      limit: 100,
    );
  }

  DateTime? get lastSuccessfulSyncAt => syncHealth?.lastSuccessfulSyncAt;

  String get dataAgeLabel {
    final last = lastSuccessfulSyncAt;
    if (last == null) return 'Bundled schedules';
    final days = DateTime.now().difference(last).inDays;
    if (days == 0) return 'Today';
    return '$days day${days == 1 ? '' : 's'}';
  }
}

enum QuickFilter {
  swimmingNow,
  withinOneHour,
  tonight,
  tomorrow,
  thisWeekend,
}
