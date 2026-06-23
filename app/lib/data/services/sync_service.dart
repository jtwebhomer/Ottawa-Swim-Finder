import '../../core/constants/app_constants.dart';
import '../../domain/entities/facility_priority.dart';
import '../../domain/entities/sync_location_context.dart';
import '../../domain/entities/sync_log.dart';
import '../../domain/entities/sync_progress.dart';
import '../../domain/entities/sync_status.dart';
import '../../domain/repositories/repositories.dart';
import '../scraper/ottawa_scraper.dart';
import 'app_version_service.dart';
import 'parser_health_service.dart';
import 'sync_health_service.dart';
import 'sync_safety_guard.dart';

class SyncService {
  SyncService({
    required OttawaScraper scraper,
    required SettingsRepository settingsRepo,
    required AppVersionService versionService,
    required ScheduleRepository scheduleRepo,
    SyncLogRepository? syncLogRepo,
    SyncHealthService? healthService,
    ParserHealthService? parserHealthService,
    SyncSafetyGuard? safetyGuard,
  })  : _scraper = scraper,
        _settingsRepo = settingsRepo,
        _versionService = versionService,
        _scheduleRepo = scheduleRepo,
        _syncLogRepo = syncLogRepo,
        _healthService = healthService ?? SyncHealthService(settingsRepo),
        _parserHealth = parserHealthService ?? ParserHealthService(settingsRepo),
        _safetyGuard = safetyGuard ?? SyncSafetyGuard();

  final OttawaScraper _scraper;
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
    final locationAnchor = anchor ?? SyncLocationContext.fallback();

    var aggregate = await runSmartPhase(
      phase: SmartSyncPhase.immediate,
      anchor: locationAnchor,
      force: force || versionOutdated,
      onProgress: onProgress,
      markRoutineComplete: false,
    );
    await onPhaseComplete?.call(SmartSyncPhase.immediate);

    if (!force && !versionOutdated && await isWithinRoutineInterval()) {
      return aggregate;
    }

    for (final phase in [SmartSyncPhase.expansion, SmartSyncPhase.background]) {
      final phaseResult = await runSmartPhase(
        phase: phase,
        anchor: locationAnchor,
        force: force || versionOutdated,
        onProgress: onProgress,
        markRoutineComplete: phase == SmartSyncPhase.background,
      );
      aggregate = _mergeResults(aggregate, phaseResult);
      await onPhaseComplete?.call(phase);
    }

    return aggregate;
  }

  Future<SyncResult> runSmartPhase({
    required SmartSyncPhase phase,
    required SyncLocationContext anchor,
    bool force = false,
    SyncProgressCallback? onProgress,
    bool markRoutineComplete = true,
  }) async {
    final attemptAt = DateTime.now().millisecondsSinceEpoch;
    await _settingsRepo.setLastSyncAttemptAt(attemptAt);

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
    var aggregate = await _runSync(
      force: true,
      isOnboarding: isOnboarding,
      phase: SmartSyncPhase.immediate,
      anchor: locationAnchor,
      onProgress: onProgress,
      markRoutineComplete: false,
    );
    await onPhaseComplete?.call(SmartSyncPhase.immediate);

    for (final phase in [SmartSyncPhase.expansion, SmartSyncPhase.background]) {
      final phaseResult = await _runSync(
        force: true,
        isOnboarding: isOnboarding,
        phase: phase,
        anchor: locationAnchor,
        onProgress: onProgress,
        markRoutineComplete: phase == SmartSyncPhase.background,
      );
      aggregate = _mergeResults(aggregate, phaseResult);
      await onPhaseComplete?.call(phase);
    }

    return aggregate;
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
    final result = await _scraper.syncAll(
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

    if (healthy && markRoutineComplete) {
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

  SyncResult _mergeResults(SyncResult a, SyncResult b) {
    final worstStatus = _worstStatus(a.syncStatus, b.syncStatus);
    return SyncResult(
      syncStatus: worstStatus,
      updated: a.updated + b.updated,
      skipped: a.skipped + b.skipped,
      errors: a.errors + b.errors,
      rejected: a.rejected + b.rejected,
      blocked: a.blocked + b.blocked,
      parseEmpty: a.parseEmpty + b.parseEmpty,
      pipelineCrashes: a.pipelineCrashes + b.pipelineCrashes,
      staleCount: a.staleCount + b.staleCount,
      http403Count: a.http403Count + b.http403Count,
      scheduleCountBefore: a.scheduleCountBefore,
      scheduleCountAfter: b.scheduleCountAfter,
      totalFacilities: b.totalFacilities,
      antiCorruptionTriggered:
          a.antiCorruptionTriggered || b.antiCorruptionTriggered,
      antiCorruptionReason: b.antiCorruptionReason ?? a.antiCorruptionReason,
      rootCauseSummary: b.rootCauseSummary ?? a.rootCauseSummary,
      facilitiesParsed: a.facilitiesParsed + b.facilitiesParsed,
      successRate: (a.successRate + b.successRate) / 2,
      projectedFutureSessions: b.projectedFutureSessions,
      failedFacilityNames: [...a.failedFacilityNames, ...b.failedFacilityNames],
      staleFacilityNames: [...a.staleFacilityNames, ...b.staleFacilityNames],
      blockedFacilityNames: [...a.blockedFacilityNames, ...b.blockedFacilityNames],
      parseEmptyFacilityNames: [
        ...a.parseEmptyFacilityNames,
        ...b.parseEmptyFacilityNames,
      ],
      facilityDiagnostics: [...a.facilityDiagnostics, ...b.facilityDiagnostics],
    );
  }

  SyncStatus _worstStatus(SyncStatus a, SyncStatus b) {
    if (a == SyncStatus.failed || b == SyncStatus.failed) {
      return SyncStatus.failed;
    }
    if (a == SyncStatus.partialSuccess || b == SyncStatus.partialSuccess) {
      return SyncStatus.partialSuccess;
    }
    return SyncStatus.success;
  }

  Future<SyncHealthSnapshot> healthSnapshot() => _healthService.load();

  Future<ParserHealthSnapshot> parserHealthSnapshot() => _parserHealth.load();

  Future<SyncLogEntry?> lastFullyCleanSync() async =>
      _syncLogRepo?.getLastFullyCleanSync();
}
