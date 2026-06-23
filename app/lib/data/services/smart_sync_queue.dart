import '../../core/constants/sync_rate_limit_policy.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/facility_priority.dart';
import '../../domain/entities/facility_score.dart';
import '../../domain/entities/sync_location_context.dart';
import '../../domain/entities/sync_status.dart';
import 'facility_priority_service.dart';

/// Builds a score-driven facility refresh queue for smart sync.
class SmartSyncQueue {
  SmartSyncQueue(this._priorityService);

  final FacilityPriorityService _priorityService;

  Future<SmartSyncBatch> planBatch({
    required List<Facility> facilities,
    required SmartSyncPhase phase,
    required SyncLocationContext anchor,
    required bool force,
    required int staleThresholdHours,
    Set<String> backoffFacilityIds = const {},
    int rotationIndex = 0,
    DateTime? now,
  }) async {
    if (facilities.isEmpty) {
      return SmartSyncBatch(phase: phase, facilityIds: const [], rankings: const []);
    }

    final clock = now ?? DateTime.now();
    final context = await _priorityService.buildContext(
      facilities: facilities,
      anchor: anchor,
      staleThresholdHours: staleThresholdHours,
      now: clock,
    );

    final rankings = _priorityService.rankFacilities(
      facilities: facilities,
      context: context,
      backoffFacilityIds: backoffFacilityIds,
    );

    final rankingById = {for (final r in rankings) r.facilityId: r};
    final orderedIds = rankings.map((r) => r.facilityId).toList();

    final staleBeforeMs =
        clock.subtract(Duration(hours: staleThresholdHours)).millisecondsSinceEpoch;

    bool needsRefresh(Facility facility) {
      if (backoffFacilityIds.contains(facility.id)) return false;
      if (force) return true;
      if (facility.syncStatus == FacilitySyncStatus.failed) return true;
      if (facility.syncStatus == FacilitySyncStatus.stale) return true;
      final lastOk = facility.lastSuccessfulSyncAt;
      if (lastOk == null) return true;
      return lastOk < staleBeforeMs;
    }

    final eligible = orderedIds
        .map((id) => facilities.firstWhere((f) => f.id == id))
        .where(needsRefresh)
        .toList();

    final batchSize = _batchSizeForPhase(phase, force: force);

    List<Facility> selected;
    if (phase == SmartSyncPhase.background && eligible.length > batchSize) {
      final start = rotationIndex % eligible.length;
      final rotated = [
        ...eligible.sublist(start),
        ...eligible.sublist(0, start),
      ];
      selected = rotated.take(batchSize).toList();
    } else {
      selected = eligible.take(batchSize).toList();
    }

    if (phase == SmartSyncPhase.immediate &&
        selected.isEmpty &&
        !force) {
      selected = orderedIds
          .map((id) => facilities.firstWhere((f) => f.id == id))
          .where((f) => !backoffFacilityIds.contains(f.id))
          .take(SyncRateLimitPolicy.phase1MinFacilityCount)
          .toList();
    }

    final selectedRankings = selected
        .map((f) => rankingById[f.id]!)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return SmartSyncBatch(
      phase: phase,
      facilityIds: selected.map((f) => f.id).toList(),
      rankings: selectedRankings,
    );
  }

  int nextRotationIndex({
    required int currentIndex,
    required int selectedCount,
    required int eligibleCount,
  }) {
    if (eligibleCount <= 0 || selectedCount <= 0) return currentIndex;
    return (currentIndex + selectedCount) % eligibleCount;
  }

  int _batchSizeForPhase(SmartSyncPhase phase, {required bool force}) {
    return switch (phase) {
      SmartSyncPhase.immediate => SyncRateLimitPolicy.phase1FacilityCount,
      SmartSyncPhase.expansion => force
          ? SyncRateLimitPolicy.onboardingFacilitiesPerSync
          : SyncRateLimitPolicy.phase2FacilityCount,
      SmartSyncPhase.background => SyncRateLimitPolicy.phase3FacilityCount,
    };
  }
}
