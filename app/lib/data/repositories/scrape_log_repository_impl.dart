import '../../domain/entities/scrape_log.dart';
import '../../domain/repositories/repositories.dart';
import '../database/app_database.dart';

class ScrapeLogRepositoryImpl implements ScrapeLogRepository {
  ScrapeLogRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<void> insertLog(ScrapeLog log) async {
    final database = await _db.database;
    await database.insert('scrape_logs', {
      'facility_id': log.facilityId,
      'status': log.status,
      'message': log.message,
      'html_snapshot_path': log.htmlSnapshotPath,
      'content_hash': log.contentHash,
      'duration_ms': log.durationMs,
      'created_at': log.createdAt,
    });
  }

  @override
  Future<List<ScrapeLog>> getRecentLogs({int limit = 50}) async {
    final database = await _db.database;
    final rows = await database.query(
      'scrape_logs',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(_fromMap).toList();
  }

  @override
  Future<List<ScrapeLog>> getErrors({int limit = 20}) async {
    final database = await _db.database;
    final rows = await database.query(
      'scrape_logs',
      where: "status = 'error'",
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(_fromMap).toList();
  }

  ScrapeLog _fromMap(Map<String, Object?> map) {
    return ScrapeLog(
      id: map['id'] as int?,
      facilityId: map['facility_id'] as String?,
      status: map['status'] as String,
      message: map['message'] as String?,
      htmlSnapshotPath: map['html_snapshot_path'] as String?,
      contentHash: map['content_hash'] as String?,
      durationMs: map['duration_ms'] as int?,
      createdAt: map['created_at'] as int,
    );
  }
}
