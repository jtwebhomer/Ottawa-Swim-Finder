import 'package:sqflite/sqflite.dart';

import '../../domain/entities/facility_interaction.dart';
import '../../domain/repositories/repositories.dart';
import '../database/app_database.dart';

class FacilityInteractionRepositoryImpl implements FacilityInteractionRepository {
  FacilityInteractionRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<FacilityInteractionMetrics> getMetrics(String facilityId) async {
    final database = await _db.database;
    final rows = await database.query(
      'facility_interactions',
      where: 'facility_id = ?',
      whereArgs: [facilityId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return FacilityInteractionMetrics(facilityId: facilityId);
    }
    return _fromRow(rows.first);
  }

  @override
  Future<Map<String, FacilityInteractionMetrics>> getAllMetrics() async {
    final database = await _db.database;
    final rows = await database.query('facility_interactions');
    return {
      for (final row in rows)
        row['facility_id'] as String: _fromRow(row),
    };
  }

  @override
  Future<void> incrementView(String facilityId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _upsert(
      facilityId,
      '''
      INSERT INTO facility_interactions (facility_id, view_count, last_viewed_at)
      VALUES (?, 1, ?)
      ON CONFLICT(facility_id) DO UPDATE SET
        view_count = view_count + 1,
        last_viewed_at = ?
      ''',
      [facilityId, now, now],
    );
  }

  @override
  Future<void> incrementSwimDetailClick(String facilityId) async {
    await _upsert(
      facilityId,
      '''
      INSERT INTO facility_interactions (facility_id, swim_detail_clicks)
      VALUES (?, 1)
      ON CONFLICT(facility_id) DO UPDATE SET
        swim_detail_clicks = swim_detail_clicks + 1
      ''',
      [facilityId],
    );
  }

  @override
  Future<void> incrementSaved(String facilityId) async {
    await _upsert(
      facilityId,
      '''
      INSERT INTO facility_interactions (facility_id, saved_count)
      VALUES (?, 1)
      ON CONFLICT(facility_id) DO UPDATE SET
        saved_count = saved_count + 1
      ''',
      [facilityId],
    );
  }

  @override
  Future<void> decrementSaved(String facilityId) async {
    await _upsert(
      facilityId,
      '''
      INSERT INTO facility_interactions (facility_id, saved_count)
      VALUES (?, 0)
      ON CONFLICT(facility_id) DO UPDATE SET
        saved_count = CASE WHEN saved_count > 0 THEN saved_count - 1 ELSE 0 END
      ''',
      [facilityId],
    );
  }

  @override
  Future<void> incrementImpression(String facilityId) async {
    await _upsert(
      facilityId,
      '''
      INSERT INTO facility_interactions (facility_id, impression_count)
      VALUES (?, 1)
      ON CONFLICT(facility_id) DO UPDATE SET
        impression_count = impression_count + 1
      ''',
      [facilityId],
    );
  }

  @override
  Future<void> incrementIgnore(String facilityId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _upsert(
      facilityId,
      '''
      INSERT INTO facility_interactions (facility_id, ignore_count, last_ignored_at)
      VALUES (?, 1, ?)
      ON CONFLICT(facility_id) DO UPDATE SET
        ignore_count = ignore_count + 1,
        last_ignored_at = ?
      ''',
      [facilityId, now, now],
    );
  }

  Future<void> _upsert(
    String facilityId,
    String sql,
    List<Object?> args,
  ) async {
    final database = await _db.database;
    await database.rawInsert(sql, args);
  }

  FacilityInteractionMetrics _fromRow(Map<String, Object?> row) {
    return FacilityInteractionMetrics(
      facilityId: row['facility_id'] as String,
      viewCount: row['view_count'] as int? ?? 0,
      lastViewedAt: row['last_viewed_at'] as int?,
      savedCount: row['saved_count'] as int? ?? 0,
      swimDetailClicks: row['swim_detail_clicks'] as int? ?? 0,
      impressionCount: row['impression_count'] as int? ?? 0,
      ignoreCount: row['ignore_count'] as int? ?? 0,
      lastIgnoredAt: row['last_ignored_at'] as int?,
    );
  }
}
