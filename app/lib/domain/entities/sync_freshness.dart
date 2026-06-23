/// Progressive sync coverage and freshness exposed to the UI.
class SyncFreshnessSnapshot {
  const SyncFreshnessSnapshot({
    required this.totalSwimFacilities,
    required this.facilitiesWithSchedules,
    required this.facilitiesFresh,
    required this.completenessPercent,
    required this.isSeedDataPresent,
    this.seedBundledAt,
    this.lastOverallSyncAt,
    this.lastLiveSyncAt,
  });

  final int totalSwimFacilities;
  final int facilitiesWithSchedules;
  final int facilitiesFresh;
  final double completenessPercent;
  final bool isSeedDataPresent;
  final DateTime? seedBundledAt;
  final DateTime? lastOverallSyncAt;
  final DateTime? lastLiveSyncAt;

  bool get isFullySynced =>
      totalSwimFacilities > 0 && facilitiesFresh >= totalSwimFacilities;

  String get completenessLabel {
    if (totalSwimFacilities == 0) return 'No swim facilities';
    return '${completenessPercent.round()}% up to date';
  }
}
