import '../../domain/entities/sync_log.dart';
import '../../domain/entities/sync_status.dart';
import '../../domain/repositories/repositories.dart';
import '../database/app_database.dart';

class SyncLogRepositoryImpl implements SyncLogRepository {
  SyncLogRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<int> insertLog(SyncLogEntry log) async {
    final database = await _db.database;
    return database.insert('sync_logs', _toMap(log));
  }

  @override
  Future<List<SyncLogEntry>> getRecentLogs({int limit = 20}) async {
    final database = await _db.database;
    final rows = await database.query(
      'sync_logs',
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(_fromMap).toList();
  }

  @override
  Future<SyncLogEntry?> getLastFullyCleanSync() async {
    final database = await _db.database;
    final rows = await database.query(
      'sync_logs',
      where: "status = ? AND anti_corruption_triggered = 0",
      whereArgs: [SyncStatus.success.label],
      orderBy: 'completed_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromMap(rows.first);
  }

  Map<String, Object?> _toMap(SyncLogEntry log) => {
        if (log.id != null) 'id': log.id,
        'started_at': log.startedAt,
        'completed_at': log.completedAt,
        'status': log.status.label,
        'success_rate': log.successRate,
        'facilities_total': log.facilitiesTotal,
        'facilities_updated': log.facilitiesUpdated,
        'facilities_skipped': log.facilitiesSkipped,
        'facilities_blocked': log.facilitiesBlocked,
        'facilities_failed': log.facilitiesFailed,
        'facilities_stale': log.facilitiesStale,
        'schedule_count_before': log.scheduleCountBefore,
        'schedule_count_after': log.scheduleCountAfter,
        'message': log.message,
        'anti_corruption_triggered': log.antiCorruptionTriggered ? 1 : 0,
      };

  SyncLogEntry _fromMap(Map<String, Object?> map) {
    final statusLabel = map['status'] as String;
    final status = SyncStatus.values.firstWhere(
      (s) => s.label == statusLabel,
      orElse: () => SyncStatus.failed,
    );
    return SyncLogEntry(
      id: map['id'] as int?,
      startedAt: map['started_at'] as int,
      completedAt: map['completed_at'] as int?,
      status: status,
      successRate: map['success_rate'] as double?,
      facilitiesTotal: map['facilities_total'] as int? ?? 0,
      facilitiesUpdated: map['facilities_updated'] as int? ?? 0,
      facilitiesSkipped: map['facilities_skipped'] as int? ?? 0,
      facilitiesBlocked: map['facilities_blocked'] as int? ?? 0,
      facilitiesFailed: map['facilities_failed'] as int? ?? 0,
      facilitiesStale: map['facilities_stale'] as int? ?? 0,
      scheduleCountBefore: map['schedule_count_before'] as int? ?? 0,
      scheduleCountAfter: map['schedule_count_after'] as int? ?? 0,
      message: map['message'] as String?,
      antiCorruptionTriggered: (map['anti_corruption_triggered'] as int? ?? 0) == 1,
    );
  }
}
