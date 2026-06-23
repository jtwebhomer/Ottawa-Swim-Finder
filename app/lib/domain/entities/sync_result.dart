import '../entities/facility_sync_diagnostic.dart';
import 'sync_status.dart';

/// Result of a schedule sync run (API pull or legacy scraper).
class SyncResult {
  const SyncResult({
    required this.syncStatus,
    required this.updated,
    required this.skipped,
    required this.errors,
    this.rejected = 0,
    this.blocked = 0,
    this.parseEmpty = 0,
    this.pipelineCrashes = 0,
    this.staleCount = 0,
    this.http403Count = 0,
    this.scheduleCountBefore = 0,
    this.scheduleCountAfter = 0,
    this.totalFacilities = 0,
    this.antiCorruptionTriggered = false,
    this.antiCorruptionReason,
    this.rootCauseSummary,
    this.facilitiesParsed = 0,
    this.successRate = 1.0,
    this.projectedFutureSessions = 0,
    this.failedFacilityNames = const [],
    this.staleFacilityNames = const [],
    this.blockedFacilityNames = const [],
    this.parseEmptyFacilityNames = const [],
    this.facilityDiagnostics = const [],
    this.backendFreshnessScore,
    this.isOffline = false,
  });

  final SyncStatus syncStatus;
  final int updated;
  final int skipped;
  final int errors;
  final int rejected;
  final int blocked;
  final int parseEmpty;
  final int pipelineCrashes;
  final int staleCount;
  final int http403Count;
  final int scheduleCountBefore;
  final int scheduleCountAfter;
  final int totalFacilities;
  final bool antiCorruptionTriggered;
  final String? antiCorruptionReason;
  final String? rootCauseSummary;
  final int facilitiesParsed;
  final double successRate;
  final int projectedFutureSessions;
  final List<String> failedFacilityNames;
  final List<String> staleFacilityNames;
  final List<String> blockedFacilityNames;
  final List<String> parseEmptyFacilityNames;
  final List<FacilitySyncDiagnostic> facilityDiagnostics;
  final double? backendFreshnessScore;
  final bool isOffline;

  bool get globalRejected => antiCorruptionTriggered;
  String? get globalRejectReason => antiCorruptionReason;
  bool get success => syncStatus == SyncStatus.success;
  bool get isHealthy =>
      !antiCorruptionTriggered &&
      (scheduleCountAfter > 0 ||
          (scheduleCountAfter >= scheduleCountBefore && errors < totalFacilities));

  String get statusLabel => switch (syncStatus) {
        SyncStatus.success => 'success',
        SyncStatus.partialSuccess => 'partial',
        SyncStatus.failed => 'failed',
      };

  bool get isMostlyBlocked =>
      blocked > 0 && blocked >= (totalFacilities * 0.5).ceil();

  bool get isFirstInstallBlocked =>
      scheduleCountAfter == 0 && blocked > 0 && errors == 0;
}
