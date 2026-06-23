import '../../core/constants/sync_rate_limit_policy.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/sync_status.dart';

/// Chooses a small, prioritized subset of facilities to refresh per sync run.
class PartialRefreshPlanner {
  const PartialRefreshPlanner();

  /// Returns facility IDs that should receive a network fetch this run.
  List<Facility> selectFacilitiesForRefresh({
    required List<Facility> facilities,
    required bool force,
    required bool isOnboarding,
    required int staleThresholdHours,
    required int rotationIndex,
    Set<String> backoffFacilityIds = const {},
    DateTime? now,
  }) {
    if (facilities.isEmpty) return [];

    final clock = now ?? DateTime.now();
    final staleBeforeMs =
        clock.subtract(Duration(hours: staleThresholdHours)).millisecondsSinceEpoch;

    final needsRefresh = facilities.where((f) {
      if (backoffFacilityIds.contains(f.id)) return false;
      if (force) return true;
      if (f.syncStatus == FacilitySyncStatus.failed) return true;
      if (f.syncStatus == FacilitySyncStatus.stale) return true;
      final lastOk = f.lastSuccessfulSyncAt;
      if (lastOk == null) return true;
      return lastOk < staleBeforeMs;
    }).toList();

    if (needsRefresh.isEmpty) return [];

    needsRefresh.sort((a, b) {
      final fav = (b.isFavorite ? 1 : 0) - (a.isFavorite ? 1 : 0);
      if (fav != 0) return fav;

      final statusRank = _statusRank(a.syncStatus) - _statusRank(b.syncStatus);
      if (statusRank != 0) return statusRank;

      final aSync = a.lastSuccessfulSyncAt ?? 0;
      final bSync = b.lastSuccessfulSyncAt ?? 0;
      return aSync.compareTo(bSync);
    });

    final batchSize = isOnboarding
        ? SyncRateLimitPolicy.onboardingFacilitiesPerSync
        : SyncRateLimitPolicy.facilitiesPerPartialSync;

    if (force && isOnboarding) {
      return needsRefresh.take(batchSize).toList();
    }

    if (!force) {
      return needsRefresh.take(batchSize).toList();
    }

    // Manual force sync: refresh all stale / never-synced, still capped per run.
    final start = rotationIndex % needsRefresh.length;
    final rotated = [
      ...needsRefresh.sublist(start),
      ...needsRefresh.sublist(0, start),
    ];
    return rotated.take(batchSize).toList();
  }

  int nextRotationIndex({
    required int currentIndex,
    required int selectedCount,
    required int eligibleCount,
  }) {
    if (eligibleCount <= 0 || selectedCount <= 0) return currentIndex;
    return (currentIndex + selectedCount) % eligibleCount;
  }

  int _statusRank(FacilitySyncStatus status) => switch (status) {
        FacilitySyncStatus.failed => 0,
        FacilitySyncStatus.stale => 1,
        FacilitySyncStatus.ok => 2,
      };
}
