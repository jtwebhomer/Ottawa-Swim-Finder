import '../../data/services/schedule_trust_resolver.dart';
import 'schedule_trust_status.dart';

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
    this.trustSummary,
    this.lastVerifiedAt,
    this.syncBlocked = false,
  });

  final int totalSwimFacilities;
  final int facilitiesWithSchedules;
  final int facilitiesFresh;
  final double completenessPercent;
  final bool isSeedDataPresent;
  final DateTime? seedBundledAt;
  final DateTime? lastOverallSyncAt;
  final DateTime? lastLiveSyncAt;
  final ScheduleTrustSummary? trustSummary;
  final DateTime? lastVerifiedAt;
  final bool syncBlocked;

  bool get isFullySynced =>
      totalSwimFacilities > 0 && facilitiesFresh >= totalSwimFacilities;

  String get completenessLabel {
    if (totalSwimFacilities == 0) return 'No swim facilities';
    return '${completenessPercent.round()}% up to date';
  }
}
