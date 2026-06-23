/// Live sync progress for UI during an active sync run.
class SyncProgress {
  const SyncProgress({
    required this.totalFacilities,
    required this.updated,
    required this.blocked,
    required this.pending,
    required this.failed,
    this.currentFacilityName,
    this.phase = SyncPhase.fetching,
  });

  final int totalFacilities;
  final int updated;
  final int blocked;
  final int pending;
  final int failed;
  final String? currentFacilityName;
  final SyncPhase phase;

  int get completed => updated + blocked + failed;

  SyncProgress copyWith({
    int? totalFacilities,
    int? updated,
    int? blocked,
    int? pending,
    int? failed,
    String? currentFacilityName,
    SyncPhase? phase,
  }) {
    return SyncProgress(
      totalFacilities: totalFacilities ?? this.totalFacilities,
      updated: updated ?? this.updated,
      blocked: blocked ?? this.blocked,
      pending: pending ?? this.pending,
      failed: failed ?? this.failed,
      currentFacilityName: currentFacilityName ?? this.currentFacilityName,
      phase: phase ?? this.phase,
    );
  }
}

enum SyncPhase {
  fetching,
  validating,
  committing,
}

typedef SyncProgressCallback = void Function(SyncProgress progress);
