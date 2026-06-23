import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/geo_utils.dart';
import '../../core/utils/ottawa_time.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/repositories/repositories.dart';
import '../database/app_database.dart';

class ScheduleRepositoryImpl implements ScheduleRepository {
  ScheduleRepositoryImpl(this._db);

  final AppDatabase _db;

  /// Categories stored in SQLite (includes legacy values pre-normalization).
  static const _dbCategories = [
    ...SwimCategories.all,
    'public_swim',
    'open_swim',
    'other',
  ];

  @override
  Future<List<ScheduleEntry>> searchSchedules({
    List<String>? categories,
    String? facilityId,
    String? date,
    String? startAfter,
    String? endBefore,
    double? maxDistanceKm,
    double? userLat,
    double? userLng,
    bool favoritesFirst = false,
  }) async {
    final database = await _db.database;
    final where = <String>[];
    final args = <Object?>[];

    if (categories != null && categories.isNotEmpty) {
      final expanded = _expandCategoryFilter(categories);
      where.add('s.category IN (${List.filled(expanded.length, '?').join(',')})');
      args.addAll(expanded);
    }
    if (facilityId != null) {
      where.add('s.facility_id = ?');
      args.add(facilityId);
    }
    if (date != null) {
      where.add('s.date = ?');
      args.add(date);
    }
    if (startAfter != null) {
      where.add('s.start_time >= ?');
      args.add(startAfter);
    }
    if (endBefore != null) {
      where.add('s.end_time <= ?');
      args.add(endBefore);
    }

    final whereClause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';

    final rows = await database.rawQuery('''
      SELECT s.*, f.name AS facility_name, f.latitude, f.longitude,
        CASE WHEN fav.facility_id IS NOT NULL THEN 1 ELSE 0 END AS is_favorite
      FROM schedules s
      INNER JOIN facilities f ON s.facility_id = f.id
      LEFT JOIN favorites fav ON f.id = fav.facility_id
      $whereClause
      ORDER BY ${favoritesFirst ? 'is_favorite DESC, ' : ''}s.date ASC, s.start_time ASC
    ''', args);

    var entries = rows.map((row) => _fromMap(row, userLat, userLng)).toList();

    if (maxDistanceKm != null && userLat != null && userLng != null) {
      entries = entries
          .where((e) => (e.distanceKm ?? double.infinity) <= maxDistanceKm)
          .toList();
    }

    if (userLat != null && userLng != null) {
      entries.sort((a, b) {
        if (favoritesFirst) {
          final rowA = rows.firstWhere((r) => r['facility_id'] == a.facilityId);
          final rowB = rows.firstWhere((r) => r['facility_id'] == b.facilityId);
          final favA = rowA['is_favorite'] as int? ?? 0;
          final favB = rowB['is_favorite'] as int? ?? 0;
          if (favA != favB) return favB.compareTo(favA);
        }
        return (a.distanceKm ?? double.infinity)
            .compareTo(b.distanceKm ?? double.infinity);
      });
    }

    return entries;
  }

  @override
  Future<List<ScheduleEntry>> getSchedulesForFacility(
    String facilityId, {
    String? date,
  }) async {
    return searchSchedules(facilityId: facilityId, date: date);
  }

  @override
  Future<List<ScheduleEntry>> getActiveNow() async {
    final date = OttawaTime.todayDate();
    final time = OttawaTime.nowTime();

    final database = await _db.database;
    final rows = await database.rawQuery('''
      SELECT s.*, f.name AS facility_name, f.latitude, f.longitude
      FROM schedules s
      INNER JOIN facilities f ON s.facility_id = f.id
      WHERE s.date = ? AND s.start_time <= ? AND s.end_time > ?
        AND s.category IN (${_dbCategories.map((_) => '?').join(',')})
      ORDER BY s.start_time ASC
    ''', [date, time, time, ..._dbCategories]);

    return rows.map((row) => _fromMap(row, null, null)).toList();
  }

  @override
  Future<List<ScheduleEntry>> getTimelineForDate(String date, {String? facilityId}) async {
    final database = await _db.database;
    final args = <Object?>[date, ..._dbCategories];
    var facilityClause = '';
    if (facilityId != null) {
      facilityClause = 'AND s.facility_id = ?';
      args.add(facilityId);
    }
    final rows = await database.rawQuery('''
      SELECT s.*, f.name AS facility_name, f.latitude, f.longitude
      FROM schedules s
      INNER JOIN facilities f ON s.facility_id = f.id
      WHERE s.date = ?
        AND s.category IN (${_dbCategories.map((_) => '?').join(',')})
        $facilityClause
      ORDER BY s.start_time ASC, f.name ASC
    ''', args);

    return rows.map((row) => _fromMap(row, null, null)).toList();
  }

  @override
  Future<List<ScheduleEntry>> findSwimsActiveAt({
    required String date,
    required String time,
    double? userLat,
    double? userLng,
  }) async {
    final database = await _db.database;
    final rows = await database.rawQuery('''
      SELECT s.*, f.name AS facility_name, f.latitude, f.longitude
      FROM schedules s
      INNER JOIN facilities f ON s.facility_id = f.id
      WHERE s.date = ?
        AND s.start_time <= ?
        AND s.end_time > ?
        AND s.category IN (${_dbCategories.map((_) => '?').join(',')})
      ORDER BY s.start_time ASC
    ''', [date, time, time, ..._dbCategories]);

    var entries = rows.map((row) => _fromMap(row, userLat, userLng)).toList();
    if (userLat != null && userLng != null) {
      entries.sort(
        (a, b) => (a.distanceKm ?? double.infinity)
            .compareTo(b.distanceKm ?? double.infinity),
      );
    }
    return entries;
  }

  @override
  Future<List<ScheduleEntry>> findSwimsAfter({
    required String date,
    required String time,
    double? userLat,
    double? userLng,
    int limit = 50,
  }) async {
    final database = await _db.database;
    final rows = await database.rawQuery('''
      SELECT s.*, f.name AS facility_name, f.latitude, f.longitude
      FROM schedules s
      INNER JOIN facilities f ON s.facility_id = f.id
      WHERE s.date = ?
        AND s.start_time >= ?
        AND s.category IN (${_dbCategories.map((_) => '?').join(',')})
      ORDER BY s.start_time ASC
      LIMIT ?
    ''', [date, time, ..._dbCategories, limit]);

    var entries = rows.map((row) => _fromMap(row, userLat, userLng)).toList();
    if (userLat != null && userLng != null) {
      entries.sort(
        (a, b) => (a.distanceKm ?? double.infinity)
            .compareTo(b.distanceKm ?? double.infinity),
      );
    }
    return entries;
  }

  static List<String> _expandCategoryFilter(List<String> categories) {
    final expanded = <String>{...categories};
    for (final cat in categories) {
      if (cat == SwimCategories.generalSwim) {
        expanded.addAll(['public_swim', 'open_swim', 'other']);
      }
    }
    return expanded.toList();
  }

  @override
  Future<void> upsertSchedules(String facilityId, List<ScheduleEntry> entries) async {
    final database = await _db.database;
    final batch = database.batch();
    final now = DateTime.now().millisecondsSinceEpoch;

    for (final entry in entries) {
      batch.insert('schedules', {
        'facility_id': facilityId,
        'category': entry.category,
        'raw_category': entry.rawCategory,
        'schedule_type': entry.scheduleType,
        'day_of_week': entry.dayOfWeek,
        'date': entry.date,
        'start_time': entry.startTime,
        'end_time': entry.endTime,
        'notes': entry.notes,
        'date_range_start': entry.dateRangeStart,
        'date_range_end': entry.dateRangeEnd,
        'last_updated': now,
      });
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<void> deleteSchedulesForFacility(String facilityId) async {
    final database = await _db.database;
    await database.delete('schedules', where: 'facility_id = ?', whereArgs: [facilityId]);
  }

  @override
  Future<int> countSchedulesForFacility(String facilityId) async {
    final database = await _db.database;
    final result = await database.rawQuery(
      'SELECT COUNT(*) AS c FROM schedules WHERE facility_id = ?',
      [facilityId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  @override
  Future<int> countAllSchedules() async {
    final database = await _db.database;
    final result = await database.rawQuery('SELECT COUNT(*) AS c FROM schedules');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  @override
  Future<int> countSchedulesForDate(String date) async {
    final database = await _db.database;
    final result = await database.rawQuery(
      'SELECT COUNT(*) AS c FROM schedules WHERE date = ?',
      [date],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  ScheduleEntry _fromMap(
    Map<String, Object?> map,
    double? userLat,
    double? userLng,
  ) {
    double? distanceKm;
    final lat = map['latitude'] as double?;
    final lng = map['longitude'] as double?;
    if (userLat != null && userLng != null && lat != null && lng != null) {
      distanceKm = GeoUtils.distanceKm(userLat, userLng, lat, lng);
    }

    return ScheduleEntry(
      id: map['id'] as int?,
      facilityId: map['facility_id'] as String,
      category: SwimCategories.normalizeStored(map['category'] as String),
      rawCategory: map['raw_category'] as String?,
      scheduleType: map['schedule_type'] as String,
      dayOfWeek: map['day_of_week'] as int?,
      date: map['date'] as String?,
      startTime: map['start_time'] as String,
      endTime: map['end_time'] as String,
      notes: map['notes'] as String?,
      dateRangeStart: map['date_range_start'] as String?,
      dateRangeEnd: map['date_range_end'] as String?,
      lastUpdated: map['last_updated'] as int?,
      facilityName: map['facility_name'] as String?,
      distanceKm: distanceKm,
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
