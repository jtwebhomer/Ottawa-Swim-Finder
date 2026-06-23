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

  @override
  Future<List<ScheduleEntry>> searchSchedules({
    List<String>? categories,
    List<String>? rawCategories,
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

    _appendCategoryFilters(
      where: where,
      args: args,
      categories: categories,
      rawCategories: rawCategories,
    );
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
  Future<List<ScheduleEntry>> getSchedulesForFacilityBetween({
    required String facilityId,
    required String startDate,
    required String endDate,
  }) async {
    final database = await _db.database;
    final rows = await database.rawQuery('''
      SELECT s.*, f.name AS facility_name, f.latitude, f.longitude
      FROM schedules s
      INNER JOIN facilities f ON s.facility_id = f.id
      WHERE s.facility_id = ?
        AND s.date >= ?
        AND s.date <= ?
      ORDER BY s.date ASC, s.start_time ASC
    ''', [facilityId, startDate, endDate]);

    return rows.map((row) => _fromMap(row, null, null)).toList();
  }

  @override
  Future<List<CategoryAuditRow>> getCategoryAuditReport() async {
    final database = await _db.database;
    final rows = await database.rawQuery('''
      SELECT
        COALESCE(s.raw_category, s.category) AS raw_cat,
        s.category AS norm_cat,
        s.facility_id,
        f.name AS facility_name,
        COUNT(*) AS occurrences
      FROM schedules s
      INNER JOIN facilities f ON s.facility_id = f.id
      GROUP BY raw_cat, norm_cat, s.facility_id, f.name
      ORDER BY occurrences DESC, raw_cat ASC
    ''');

    return rows
        .map(
          (row) => CategoryAuditRow(
            rawCategory: row['raw_cat'] as String,
            normalizedCategory: row['norm_cat'] as String,
            facilityId: row['facility_id'] as String,
            facilityName: row['facility_name'] as String,
            occurrences: row['occurrences'] as int,
          ),
        )
        .toList();
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
      ORDER BY s.start_time ASC
    ''', [date, time, time]);

    return rows.map((row) => _fromMap(row, null, null)).toList();
  }

  @override
  Future<List<ScheduleEntry>> getTimelineForDate(String date, {String? facilityId}) async {
    final database = await _db.database;
    final args = <Object?>[date];
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
      ORDER BY s.start_time ASC
    ''', [date, time, time]);

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
    List<String>? categories,
    List<String>? rawCategories,
    String? facilityId,
    double? maxDistanceKm,
  }) async {
    return _queryUpcoming(
      fromDate: date,
      fromTime: time,
      sameDayOnly: true,
      limit: limit,
      categories: categories,
      rawCategories: rawCategories,
      facilityId: facilityId,
      userLat: userLat,
      userLng: userLng,
      maxDistanceKm: maxDistanceKm,
    );
  }

  @override
  Future<List<ScheduleEntry>> getUpcomingSwims({
    String? fromDate,
    String? fromTime,
    String? toDate,
    int limit = 200,
    List<String>? categories,
    List<String>? rawCategories,
    String? facilityId,
    double? userLat,
    double? userLng,
    double? maxDistanceKm,
  }) async {
    return _queryUpcoming(
      fromDate: fromDate ?? OttawaTime.todayDate(),
      fromTime: fromTime ?? OttawaTime.nowTime(),
      toDate: toDate,
      limit: limit,
      categories: categories,
      rawCategories: rawCategories,
      facilityId: facilityId,
      userLat: userLat,
      userLng: userLng,
      maxDistanceKm: maxDistanceKm,
    );
  }

  @override
  Future<List<ScheduleEntry>> findNextSwimsAfter({
    required String date,
    required String time,
    int limit = 50,
    List<String>? categories,
    List<String>? rawCategories,
    String? facilityId,
    double? userLat,
    double? userLng,
    double? maxDistanceKm,
  }) async {
    return _queryUpcoming(
      fromDate: date,
      fromTime: time,
      limit: limit,
      categories: categories,
      rawCategories: rawCategories,
      facilityId: facilityId,
      userLat: userLat,
      userLng: userLng,
      maxDistanceKm: maxDistanceKm,
    );
  }

  Future<List<ScheduleEntry>> _queryUpcoming({
    required String fromDate,
    required String fromTime,
    String? toDate,
    int limit = 200,
    List<String>? categories,
    List<String>? rawCategories,
    String? facilityId,
    double? userLat,
    double? userLng,
    double? maxDistanceKm,
    bool sameDayOnly = false,
  }) async {
    final database = await _db.database;
    final where = <String>[
      if (sameDayOnly)
        's.date = ? AND s.start_time >= ?'
      else
        '(s.date > ? OR (s.date = ? AND s.start_time >= ?))',
    ];
    final args = <Object?>[
      if (sameDayOnly) ...[fromDate, fromTime] else ...[fromDate, fromDate, fromTime],
    ];

    if (toDate != null) {
      where.add('s.date <= ?');
      args.add(toDate);
    }
    _appendCategoryFilters(
      where: where,
      args: args,
      categories: categories,
      rawCategories: rawCategories,
    );
    if (facilityId != null) {
      where.add('s.facility_id = ?');
      args.add(facilityId);
    }

    final rows = await database.rawQuery('''
      SELECT s.*, f.name AS facility_name, f.latitude, f.longitude
      FROM schedules s
      INNER JOIN facilities f ON s.facility_id = f.id
      WHERE ${where.join(' AND ')}
      ORDER BY s.date ASC, s.start_time ASC
      LIMIT ?
    ''', [...args, limit]);

    var entries = rows.map((row) => _fromMap(row, userLat, userLng)).toList();
    if (maxDistanceKm != null && userLat != null && userLng != null) {
      entries = entries
          .where((e) => (e.distanceKm ?? double.infinity) <= maxDistanceKm)
          .toList();
    }
    return entries;
  }

  @override
  Future<List<String>> getDatesWithSwims({
    required String startDate,
    required String endDate,
    List<String>? categories,
  }) async {
    final database = await _db.database;
    final where = <String>[
      's.date >= ?',
      's.date <= ?',
    ];
    final args = <Object?>[startDate, endDate];
    _appendCategoryFilters(
      where: where,
      args: args,
      categories: categories,
    );

    final rows = await database.rawQuery('''
      SELECT DISTINCT s.date AS d
      FROM schedules s
      WHERE ${where.join(' AND ')}
      ORDER BY d ASC
    ''', args);

    return rows.map((r) => r['d'] as String).toList();
  }

  @override
  Future<int> countFutureSessions(String fromDate) async {
    final database = await _db.database;
    final result = await database.rawQuery(
      'SELECT COUNT(*) AS c FROM schedules WHERE date > ?',
      [fromDate],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  @override
  Future<int> countFutureSessionsForFacility(
    String facilityId,
    String fromDate,
  ) async {
    final database = await _db.database;
    final result = await database.rawQuery(
      'SELECT COUNT(*) AS c FROM schedules WHERE facility_id = ? AND date > ?',
      [facilityId, fromDate],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  @override
  Future<List<String>> getUnknownRawCategories() async {
    final database = await _db.database;
    final rows = await database.rawQuery('''
      SELECT DISTINCT raw_category AS raw
      FROM schedules
      WHERE category = 'other' AND raw_category IS NOT NULL
      ORDER BY raw ASC
    ''');
    return rows.map((r) => r['raw'] as String).toList();
  }

  @override
  Future<List<CategoryInventoryRow>> getCategoryInventory() async {
    final database = await _db.database;
    final rows = await database.rawQuery('''
      SELECT
        COALESCE(NULLIF(TRIM(s.raw_category), ''), s.category) AS raw_cat,
        s.category AS norm_cat,
        COUNT(*) AS session_count,
        COUNT(DISTINCT s.facility_id) AS facility_count
      FROM schedules s
      GROUP BY raw_cat, norm_cat
      ORDER BY session_count DESC, raw_cat ASC
    ''');

    return rows
        .map(
          (row) => CategoryInventoryRow(
            rawCategory: row['raw_cat'] as String,
            normalizedCategory: SwimCategories.normalizeStored(
              row['norm_cat'] as String,
            ),
            facilityCount: row['facility_count'] as int,
            sessionCount: row['session_count'] as int,
          ),
        )
        .toList();
  }

  static void _appendCategoryFilters({
    required List<String> where,
    required List<Object?> args,
    List<String>? categories,
    List<String>? rawCategories,
  }) {
    final parts = <String>[];
    if (categories != null && categories.isNotEmpty) {
      final expanded = _expandCategoryFilter(categories);
      parts.add('s.category IN (${List.filled(expanded.length, '?').join(',')})');
      args.addAll(expanded);
    }
    if (rawCategories != null && rawCategories.isNotEmpty) {
      parts.add(
        'COALESCE(NULLIF(TRIM(s.raw_category), \'\'), s.category) IN (${List.filled(rawCategories.length, '?').join(',')})',
      );
      args.addAll(rawCategories);
    }
    if (parts.isEmpty) return;
    where.add(parts.length == 1 ? parts.single : '(${parts.join(' OR ')})');
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
  Future<void> replaceSchedulesForFacility(
    String facilityId,
    List<ScheduleEntry> entries,
  ) async {
    final database = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await database.transaction((txn) async {
      await txn.delete(
        'schedules',
        where: 'facility_id = ?',
        whereArgs: [facilityId],
      );

      final batch = txn.batch();
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
    });
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
  Future<int> countSchedulesForFacilityOnDate(String facilityId, String date) async {
    final database = await _db.database;
    final result = await database.rawQuery(
      'SELECT COUNT(*) AS c FROM schedules WHERE facility_id = ? AND date = ?',
      [facilityId, date],
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

  @override
  Future<Map<String, int>> getSwimCountsByDate({
    required String startDate,
    required String endDate,
  }) async {
    final database = await _db.database;
    final rows = await database.rawQuery('''
      SELECT s.date AS d, COUNT(*) AS c
      FROM schedules s
      WHERE s.date >= ? AND s.date <= ?
      GROUP BY s.date
      ORDER BY d ASC
    ''', [startDate, endDate]);

    return {for (final r in rows) r['d'] as String: r['c'] as int};
  }

  @override
  Future<Map<String, String>> getDominantCategoryByDate({
    required String startDate,
    required String endDate,
  }) async {
    final database = await _db.database;
    final rows = await database.rawQuery('''
      SELECT s.date AS d, s.category AS cat, COUNT(*) AS c
      FROM schedules s
      WHERE s.date >= ? AND s.date <= ?
      GROUP BY s.date, s.category
      ORDER BY s.date ASC, c DESC
    ''', [startDate, endDate]);

    final map = <String, String>{};
    for (final r in rows) {
      final d = r['d'] as String;
      map.putIfAbsent(d, () => SwimCategories.normalizeStored(r['cat'] as String));
    }
    return map;
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
}
