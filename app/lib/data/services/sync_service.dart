import '../../core/constants/app_constants.dart';
import '../../domain/repositories/repositories.dart';
import '../scraper/ottawa_scraper.dart';
import 'sync_health_service.dart';
import 'sync_safety_guard.dart';

class SyncService {
  SyncService({
    required OttawaScraper scraper,
    required SettingsRepository settingsRepo,
    SyncHealthService? healthService,
    SyncSafetyGuard? safetyGuard,
  })  : _scraper = scraper,
        _settingsRepo = settingsRepo,
        _healthService = healthService ?? SyncHealthService(settingsRepo),
        _safetyGuard = safetyGuard ?? SyncSafetyGuard();

  final OttawaScraper _scraper;
  final SettingsRepository _settingsRepo;
  final SyncHealthService _healthService;
  final SyncSafetyGuard _safetyGuard;

  Future<SyncResult> syncIfNeeded({bool force = false}) async {
    if (!force) {
      final lastSync = await _settingsRepo.getLastSyncAt();
      final hoursSince =
          (DateTime.now().millisecondsSinceEpoch - lastSync) / (1000 * 60 * 60);
      if (hoursSince < AppConstants.syncIntervalHours) {
        return const SyncResult(updated: 0, skipped: 0, errors: 0);
      }
    }

    final result = await _scraper.syncAll(force: force);

    await _healthService.recordSyncResult(
      status: result.statusLabel,
      scheduleCountBefore: result.scheduleCountBefore,
      scheduleCountAfter: result.scheduleCountAfter,
      updated: result.updated,
      skipped: result.skipped,
      errors: result.errors,
      http403Count: result.http403Count,
    );

    final healthy = _safetyGuard.isSyncHealthy(
      totalFacilities: result.totalFacilities,
      updated: result.updated,
      skipped: result.skipped,
      errors: result.errors,
      scheduleCountBefore: result.scheduleCountBefore,
      scheduleCountAfter: result.scheduleCountAfter,
    );

    if (healthy) {
      await _settingsRepo.setLastSyncAt(DateTime.now().millisecondsSinceEpoch);
    }

    return result;
  }

  Future<SyncResult> forceSync() => syncIfNeeded(force: true);

  Future<SyncHealthSnapshot> healthSnapshot() => _healthService.load();
}
