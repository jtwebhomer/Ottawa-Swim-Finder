import 'package:sqflite/sqflite.dart';

import '../../core/utils/ottawa_time.dart';
import '../../domain/entities/saved_swim.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/repositories/repositories.dart';
import '../database/app_database.dart';

class SavedSwimRepositoryImpl implements SavedSwimRepository {
  SavedSwimRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<List<SavedSwim>> getAll({bool upcomingOnly = false}) async {
    final database = await _db.database;
    final today = OttawaTime.todayDate();
    final now = OttawaTime.nowTime();

    final rows = await database.rawQuery('''
      SELECT ss.*, f.name AS facility_name
      FROM saved_swims ss
      INNER JOIN facilities f ON ss.facility_id = f.id
      ORDER BY ss.is_recurring ASC, ss.date ASC, ss.start_time ASC
    ''');

    final swims = <SavedSwim>[];
    for (final row in rows) {
      final swim = await _fromMap(database, row);
      if (!upcomingOnly) {
        swims.add(swim);
        continue;
      }
      if (swim.isRecurring) {
        if (swim.upcomingOccurrences.isNotEmpty) swims.add(swim);
      } else if (swim.date.isNotEmpty &&
          (swim.date.compareTo(today) > 0 ||
              (swim.date == today && swim.endTime.compareTo(now) > 0))) {
        swims.add(swim);
      }
    }
    return swims;
  }

  @override
  Future<int> saveSession(ScheduleEntry entry, {int? reminderMinutes}) async {
    if (entry.date == null) return -1;
    final database = await _db.database;
    return database.insert('saved_swims', {
      'schedule_id': entry.id,
      'facility_id': entry.facilityId,
      'category': entry.category,
      'raw_category': entry.rawCategory,
      'date': entry.date,
      'start_time': entry.startTime,
      'end_time': entry.endTime,
      'reminder_minutes': reminderMinutes,
      'is_recurring': 0,
      'day_of_week': entry.dayOfWeek,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Future<int> saveRecurringPattern({
    required String facilityId,
    required String category,
    String? rawCategory,
    required int dayOfWeek,
    required String startTime,
    required String endTime,
    int? reminderMinutes,
  }) async {
    final database = await _db.database;
    return database.insert('saved_swims', {
      'facility_id': facilityId,
      'category': category,
      'raw_category': rawCategory,
      'date': '',
      'start_time': startTime,
      'end_time': endTime,
      'reminder_minutes': reminderMinutes,
      'is_recurring': 1,
      'day_of_week': dayOfWeek,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> updateReminder(int id, int? reminderMinutes) async {
    final database = await _db.database;
    await database.update(
      'saved_swims',
      {'reminder_minutes': reminderMinutes},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> remove(int id) async {
    final database = await _db.database;
    await database.delete('saved_swims', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<bool> isSaved(ScheduleEntry entry) async {
    if (entry.date == null) return false;
    final database = await _db.database;
    final rows = await database.query(
      'saved_swims',
      where:
          'is_recurring = 0 AND facility_id = ? AND date = ? AND start_time = ? AND end_time = ? AND category = ?',
      whereArgs: [
        entry.facilityId,
        entry.date,
        entry.startTime,
        entry.endTime,
        entry.category,
      ],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<SavedSwim?> getById(int id) async {
    final database = await _db.database;
    final rows = await database.rawQuery('''
      SELECT ss.*, f.name AS facility_name
      FROM saved_swims ss
      INNER JOIN facilities f ON ss.facility_id = f.id
      WHERE ss.id = ?
    ''', [id]);
    if (rows.isEmpty) return null;
    return _fromMap(database, rows.first);
  }

  Future<SavedSwim> _fromMap(
    Database database,
    Map<String, Object?> map,
  ) async {
    final isRecurring = (map['is_recurring'] as int? ?? 0) == 1;
    final dayOfWeek = map['day_of_week'] as int?;
    final facilityId = map['facility_id'] as String;
    final category = map['category'] as String;
    final startTime = map['start_time'] as String;
    final endTime = map['end_time'] as String;
    final date = map['date'] as String? ?? '';

    var upcoming = <SavedSwimOccurrence>[];
    if (isRecurring && dayOfWeek != null) {
      upcoming = await _resolveRecurringOccurrences(
        database: database,
        facilityId: facilityId,
        category: category,
        dayOfWeek: dayOfWeek,
        startTime: startTime,
        endTime: endTime,
        facilityName: map['facility_name'] as String?,
      );
    }

    return SavedSwim(
      id: map['id'] as int?,
      scheduleId: map['schedule_id'] as int?,
      facilityId: facilityId,
      category: category,
      rawCategory: map['raw_category'] as String?,
      date: date,
      startTime: startTime,
      endTime: endTime,
      reminderMinutes: map['reminder_minutes'] as int?,
      createdAt: map['created_at'] as int?,
      facilityName: map['facility_name'] as String?,
      isRecurring: isRecurring,
      dayOfWeek: dayOfWeek,
      upcomingOccurrences: upcoming,
    );
  }

  Future<List<SavedSwimOccurrence>> _resolveRecurringOccurrences({
    required Database database,
    required String facilityId,
    required String category,
    required int dayOfWeek,
    required String startTime,
    required String endTime,
    String? facilityName,
    int limit = 6,
  }) async {
    final today = OttawaTime.todayDate();
    final rows = await database.rawQuery('''
      SELECT s.date, s.start_time, s.end_time, f.name AS facility_name
      FROM schedules s
      INNER JOIN facilities f ON s.facility_id = f.id
      WHERE s.facility_id = ?
        AND s.category = ?
        AND s.start_time = ?
        AND s.end_time = ?
        AND s.date >= ?
        AND CAST(strftime('%w', s.date) AS INTEGER) = ?
      ORDER BY s.date ASC
      LIMIT ?
    ''', [
      facilityId,
      category,
      startTime,
      endTime,
      today,
      dayOfWeek % 7,
      limit,
    ]);

    return rows
        .map(
          (r) => SavedSwimOccurrence(
            date: r['date'] as String,
            startTime: r['start_time'] as String,
            endTime: r['end_time'] as String,
            facilityName: r['facility_name'] as String? ?? facilityName,
          ),
        )
        .toList();
  }
}
