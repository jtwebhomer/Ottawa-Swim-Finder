import 'package:sqflite/sqflite.dart';

import '../../domain/entities/facility.dart';
import '../../domain/entities/facility_type.dart';
import '../../domain/entities/sync_status.dart';
import '../../domain/repositories/repositories.dart';
import '../database/app_database.dart';

class FacilityRepositoryImpl implements FacilityRepository {
  FacilityRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<List<Facility>> getAllFacilities({
    bool favoritesFirst = false,
    FacilityType? facilityType,
    FacilityScheduleMode? scheduleMode,
  }) async {
    final database = await _db.database;
    final where = <String>[];
    final args = <Object?>[];

    if (facilityType != null) {
      where.add('f.facility_type = ?');
      args.add(facilityType.storageKey);
    }
    if (scheduleMode != null) {
      where.add('f.schedule_mode = ?');
      args.add(scheduleMode.storageKey);
    }

    final whereClause =
        where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

    final rows = await database.rawQuery('''
      SELECT f.*, CASE WHEN fav.facility_id IS NOT NULL THEN 1 ELSE 0 END AS is_favorite
      FROM facilities f
      LEFT JOIN favorites fav ON f.id = fav.facility_id
      $whereClause
      ORDER BY ${favoritesFirst ? 'is_favorite DESC, ' : ''}f.name ASC
    ''', args);
    return rows.map(_fromMap).toList();
  }

  @override
  Future<Facility?> getFacilityById(String id) async {
    final database = await _db.database;
    final rows = await database.rawQuery('''
      SELECT f.*, CASE WHEN fav.facility_id IS NOT NULL THEN 1 ELSE 0 END AS is_favorite
      FROM facilities f
      LEFT JOIN favorites fav ON f.id = fav.facility_id
      WHERE f.id = ?
    ''', [id]);
    if (rows.isEmpty) return null;
    return _fromMap(rows.first);
  }

  @override
  Future<void> upsertFacility(Facility facility) async {
    final database = await _db.database;
    await database.insert(
      'facilities',
      {
        'id': facility.id,
        'name': facility.name,
        'address': facility.address,
        'postal_code': facility.postalCode,
        'latitude': facility.latitude,
        'longitude': facility.longitude,
        'region': facility.region,
        'url': facility.url,
        'content_hash': facility.contentHash,
        'last_updated': facility.lastUpdated,
        'last_successful_sync_at': facility.lastSuccessfulSyncAt,
        'sync_status': facility.syncStatus.label,
        'has_pool': facility.hasSwimSchedule ? 1 : 0,
        'facility_type': facility.facilityType.storageKey,
        'schedule_mode': facility.scheduleMode.storageKey,
        'metadata_json': facility.metadataJson,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> updateSyncMetadata({
    required String facilityId,
    required FacilitySyncStatus syncStatus,
    int? lastSuccessfulSyncAt,
    String? contentHash,
    int? lastUpdated,
  }) async {
    final database = await _db.database;
    final updates = <String, Object?>{'sync_status': syncStatus.label};
    if (lastSuccessfulSyncAt != null) {
      updates['last_successful_sync_at'] = lastSuccessfulSyncAt;
    }
    if (contentHash != null) updates['content_hash'] = contentHash;
    if (lastUpdated != null) updates['last_updated'] = lastUpdated;
    await database.update(
      'facilities',
      updates,
      where: 'id = ?',
      whereArgs: [facilityId],
    );
  }

  @override
  Future<void> toggleFavorite(String facilityId, bool isFavorite) async {
    final database = await _db.database;
    if (isFavorite) {
      await database.insert(
        'favorites',
        {
          'facility_id': facilityId,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await database.delete('favorites', where: 'facility_id = ?', whereArgs: [facilityId]);
    }
  }

  @override
  Future<List<Facility>> getFavorites() async {
    final database = await _db.database;
    final rows = await database.rawQuery('''
      SELECT f.*, 1 AS is_favorite
      FROM facilities f
      INNER JOIN favorites fav ON f.id = fav.facility_id
      ORDER BY f.name ASC
    ''');
    return rows.map(_fromMap).toList();
  }

  Facility _fromMap(Map<String, Object?> map) {
    return Facility(
      id: map['id'] as String,
      name: map['name'] as String,
      address: map['address'] as String?,
      postalCode: map['postal_code'] as String?,
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      region: map['region'] as String?,
      url: map['url'] as String?,
      contentHash: map['content_hash'] as String?,
      lastUpdated: map['last_updated'] as int?,
      lastSuccessfulSyncAt: map['last_successful_sync_at'] as int?,
      syncStatus:
          FacilitySyncStatus.fromDb(map['sync_status'] as String?) ??
              FacilitySyncStatus.ok,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      metadataJson: map['metadata_json'] as String?,
      facilityType: FacilityType.fromStorage(map['facility_type'] as String?) ??
          FacilityType.indoorPool,
      scheduleMode:
          FacilityScheduleMode.fromStorage(map['schedule_mode'] as String?) ??
              FacilityScheduleMode.swimSchedule,
    );
  }
}
