import '../../core/constants/app_constants.dart';
import 'seed_database_service.dart';
import '../../core/constants/sync_rate_limit_policy.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/sync_freshness.dart';
import '../../domain/entities/sync_status.dart';
import '../../domain/repositories/repositories.dart';

/// Computes progressive sync completeness for UI surfaces.
class SyncFreshnessService {
  SyncFreshnessService({
    required FacilityRepository facilityRepo,
    required ScheduleRepository scheduleRepo,
    required SettingsRepository settingsRepo,
  })  : _facilityRepo = facilityRepo,
        _scheduleRepo = scheduleRepo,
        _settingsRepo = settingsRepo;

  final FacilityRepository _facilityRepo;
  final ScheduleRepository _scheduleRepo;
  final SettingsRepository _settingsRepo;

  Future<SyncFreshnessSnapshot> load() async {
    final facilities = await _facilityRepo.getAllFacilities();
    final swimFacilities =
        facilities.where((f) => f.hasSwimSchedule).toList();
    final staleThresholdHours = await _staleThresholdHours();
    final staleBefore = DateTime.now()
        .subtract(Duration(hours: staleThresholdHours))
        .millisecondsSinceEpoch;

    var withSchedules = 0;
    var fresh = 0;
    for (final facility in swimFacilities) {
      final count = await _scheduleRepo.countSchedulesForFacility(facility.id);
      if (count > 0) withSchedules++;
      if (_isFresh(facility, staleBefore)) fresh++;
    }

    final total = swimFacilities.length;
    final completeness = total == 0 ? 0.0 : (fresh / total) * 100;

    final seedLoadedAt = int.tryParse(
      await _settingsRepo.getString(SeedDatabaseService.seedLoadedAtKey) ?? '',
    );
    final seedBundledAt = int.tryParse(
      await _settingsRepo.getString(SeedDatabaseService.seedBundledAtKey) ?? '',
    );
    final lastSyncAt = await _settingsRepo.getLastSyncAt();

    return SyncFreshnessSnapshot(
      totalSwimFacilities: total,
      facilitiesWithSchedules: withSchedules,
      facilitiesFresh: fresh,
      completenessPercent: completeness,
      isSeedDataPresent: seedLoadedAt != null,
      seedBundledAt: seedBundledAt != null
          ? DateTime.fromMillisecondsSinceEpoch(seedBundledAt)
          : null,
      lastOverallSyncAt: lastSyncAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(lastSyncAt)
          : null,
      lastLiveSyncAt: lastSyncAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(lastSyncAt)
          : null,
    );
  }

  bool _isFresh(Facility facility, int staleBeforeMs) {
    if (facility.syncStatus != FacilitySyncStatus.ok) return false;
    final lastOk = facility.lastSuccessfulSyncAt;
    if (lastOk == null) return false;
    return lastOk >= staleBeforeMs;
  }

  Future<int> _staleThresholdHours() async {
    final raw = await _settingsRepo.getString(
      AppConstants.settingsStaleThresholdHours,
    );
    final parsed = int.tryParse(raw ?? '');
    return parsed ?? SyncRateLimitPolicy.defaultStaleThresholdHours;
  }
}
