import '../../core/constants/app_constants.dart';
import '../../domain/entities/facility_priority.dart';
import '../../domain/entities/sync_location_context.dart';
import '../../domain/entities/sync_log.dart';
import '../../domain/entities/sync_progress.dart';
import '../../domain/entities/sync_result.dart';
import '../../domain/entities/sync_status.dart';
import '../../domain/repositories/repositories.dart';
import 'app_version_service.dart';
import 'backend_sync_service.dart';
import 'parser_health_service.dart';
import 'sync_health_service.dart';
import 'sync_safety_guard.dart';

class SyncService {
  SyncService({
    required BackendSyncService backendSync,
    required SettingsRepository settingsRepo,
    required AppVersionService versionService,
    required ScheduleRepository scheduleRepo,
    SyncLogRepository? syncLogRepo,
    SyncHealthService? healthService,
    ParserHealthService? parserHealthService,
    SyncSafetyGuard? safetyGuard,
  })  : _backendSync = backendSync,
        _settingsRepo = settingsRepo,
        _versionService = versionService,
        _scheduleRepo = scheduleRepo,
        _syncLogRepo = syncLogRepo,
        _healthService = healthService ?? SyncHealthService(settingsRepo),
        _parserHealth = parserHealthService ?? ParserHealthService(settingsRepo),
        _safetyGuard = safetyGuard ?? SyncSafetyGuard();

  final BackendSyncService _backendSync;
  final SettingsRepository _settingsRepo;
  final AppVersionService _versionService;
  final ScheduleRepository _scheduleRepo;
  final SyncLogRepository? _syncLogRepo;
  final SyncHealthService _healthService;
  final ParserHealthService _parserHealth;
  final SyncSafetyGuard _safetyGuard;

  Future<bool> needsVersionSync() async {
    final current = await _versionService.fullVersionLabel();
    final lastSynced = await _settingsRepo.getLastSyncedAppVersion();
    return lastSynced == null || lastSynced != current;
  }

  Future<bool> isWithinRoutineInterval() async {
    final lastSync = await _settingsRepo.getLastSyncAt();
    if (lastSync == 0) return false;
    final hoursSince =
        (DateTime.now().millisecondsSinceEpoch - lastSync) / (1000 * 60 * 60);
    return hoursSince < AppConstants.syncIntervalHours;
  }

  Future<SyncResult> syncIfNeeded({
    bool force = false,
    SyncProgressCallback? onProgress,
    SyncLocationContext? anchor,
    Future<void> Function(SmartSyncPhase phase)? onPhaseComplete,
  }) async {
    final attemptAt = DateTime.now().millisecondsSinceEpoch;
    await _settingsRepo.setLastSyncAttemptAt(attemptAt);

    final versionOutdated = await needsVersionSync();
    if (!force && !versionOutdated && await isWithinRoutineInterval()) {
      return _cachedResult();
    }

    final locationAnchor = anchor ?? SyncLocationContext.fallback();
    final result = await _runSync(
      force: force || versionOutdated,
      anchor: locationAnchor,
      onProgress: onProgress,
      markRoutineComplete: true,
    );
    await onPhaseComplete?.call(SmartSyncPhase.background);
    return result;
  }

  Future<SyncResult> runSmartPhase({
    required SmartSyncPhase phase,
    required SyncLocationContext anchor,
    bool force = false,
    SyncProgressCallback? onProgress,
    bool markRoutineComplete = true,
  }) {
    return _runSync(
      force: force,
      phase: phase,
      anchor: anchor,
      onProgress: onProgress,
      markRoutineComplete: markRoutineComplete,
    );
  }

  Future<SyncResult> forceSync({
    SyncProgressCallback? onProgress,
    bool isOnboarding = false,
    SyncLocationContext? anchor,
    Future<void> Function(SmartSyncPhase phase)? onPhaseComplete,
  }) async {
    final locationAnchor = anchor ?? SyncLocationContext.fallback();
    final result = await _runSync(
      force: true,
      isOnboarding: isOnboarding,
      phase: SmartSyncPhase.immediate,
      anchor: locationAnchor,
      onProgress: onProgress,
      markRoutineComplete: true,
    );
    await onPhaseComplete?.call(SmartSyncPhase.immediate);
    return result;
  }

  Future<SyncResult> _runSync({
    required bool force,
    SmartSyncPhase phase = SmartSyncPhase.background,
    SyncLocationContext anchor = const SyncLocationContext(
      latitude: SyncLocationContext.fallbackLatitude,
      longitude: SyncLocationContext.fallbackLongitude,
      usesDeviceLocation: false,
    ),
    bool isOnboarding = false,
    SyncProgressCallback? onProgress,
    bool markRoutineComplete = true,
  }) async {
    final started = DateTime.now();
    final result = await _backendSync.syncAll(
      force: force,
      isOnboarding: isOnboarding,
      phase: phase,
      anchor: anchor,
      onProgress: onProgress,
    );

    final durationMs = DateTime.now().difference(started).inMilliseconds;

    await _settingsRepo.setLastSyncStatus(result.syncStatus.label);

    await _healthService.recordSyncResult(
      status: result.syncStatus.label,
      scheduleCountBefore: result.scheduleCountBefore,
      scheduleCountAfter: result.scheduleCountAfter,
      updated: result.updated,
      skipped: result.skipped,
      errors: result.errors,
      blocked: result.blocked,
      staleCount: result.staleCount,
      successRate: result.successRate,
      http403Count: result.http403Count,
      durationMs: durationMs,
    );

    if (result.antiCorruptionTriggered) {
      await _parserHealth.recordRejectedParse(
        result.antiCorruptionReason ?? 'Sync rejected — success rate too low',
      );
    }

    final healthy = _safetyGuard.isSyncHealthy(
      totalFacilities: result.totalFacilities,
      updated: result.updated,
      skipped: result.skipped,
      errors: result.errors,
      scheduleCountBefore: result.scheduleCountBefore,
      scheduleCountAfter: result.scheduleCountAfter,
      blocked: result.blocked,
      rejected: result.rejected,
      globalRejected: result.antiCorruptionTriggered,
    );

    if (healthy && markRoutineComplete && !result.isOffline) {
      await _settingsRepo.setLastSyncAt(DateTime.now().millisecondsSinceEpoch);

      final version = await _versionService.fullVersionLabel();
      await _settingsRepo.setLastSyncedAppVersion(version);

      final unknown = await _scheduleRepo.getUnknownRawCategories();
      await _parserHealth.recordSuccessfulParse(
        facilitiesParsed: result.facilitiesParsed,
        totalFacilities: result.totalFacilities,
        futureSessions: result.projectedFutureSessions,
        unknownCategories: unknown.length,
      );
    }

    return result;
  }

  Future<SyncResult> _cachedResult() async {
    final count = await _scheduleRepo.countAllSchedules();
    return SyncResult(
      syncStatus: SyncStatus.success,
      updated: 0,
      skipped: 0,
      errors: 0,
      scheduleCountBefore: count,
      scheduleCountAfter: count,
    );
  }

  Future<SyncHealthSnapshot> healthSnapshot() => _healthService.load();

  Future<ParserHealthSnapshot> parserHealthSnapshot() => _parserHealth.load();

  Future<SyncLogEntry?> lastFullyCleanSync() async =>
      _syncLogRepo?.getLastFullyCleanSync();
}
