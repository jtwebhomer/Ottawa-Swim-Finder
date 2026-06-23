import 'sync_status.dart';

/// Persisted record of a sync run (separate from per-facility scrape_logs).
class SyncLogEntry {
  const SyncLogEntry({
    this.id,
    required this.startedAt,
    this.completedAt,
    required this.status,
    this.successRate,
    this.facilitiesTotal = 0,
    this.facilitiesUpdated = 0,
    this.facilitiesSkipped = 0,
    this.facilitiesBlocked = 0,
    this.facilitiesFailed = 0,
    this.facilitiesStale = 0,
    this.scheduleCountBefore = 0,
    this.scheduleCountAfter = 0,
    this.message,
    this.antiCorruptionTriggered = false,
  });

  final int? id;
  final int startedAt;
  final int? completedAt;
  final SyncStatus status;
  final double? successRate;
  final int facilitiesTotal;
  final int facilitiesUpdated;
  final int facilitiesSkipped;
  final int facilitiesBlocked;
  final int facilitiesFailed;
  final int facilitiesStale;
  final int scheduleCountBefore;
  final int scheduleCountAfter;
  final String? message;
  final bool antiCorruptionTriggered;
}
