import '../../domain/entities/habit_event.dart';
import '../../domain/repositories/repositories.dart';
import '../database/app_database.dart';

class HabitEventRepositoryImpl implements HabitEventRepository {
  HabitEventRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<void> insertEvent(HabitEvent event) async {
    final database = await _db.database;
    await database.insert('habit_events', {
      'facility_id': event.facilityId,
      'recorded_at': event.recordedAt,
      'action_type': event.actionType.storageKey,
      'weight': event.weight,
      'day_of_week': event.dayOfWeek,
      'hour_of_day': event.hourOfDay,
      'time_bucket': event.timeBucket,
      'swim_start_time': event.swimStartTime,
    });
  }

  @override
  Future<List<HabitEvent>> eventsSince(int sinceMs) async {
    final database = await _db.database;
    final rows = await database.query(
      'habit_events',
      where: 'recorded_at >= ?',
      whereArgs: [sinceMs],
      orderBy: 'recorded_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  @override
  Future<int> countEventsSince(int sinceMs) async {
    final database = await _db.database;
    final result = await database.rawQuery(
      'SELECT COUNT(*) AS c FROM habit_events WHERE recorded_at >= ?',
      [sinceMs],
    );
    return result.first['c'] as int? ?? 0;
  }

  @override
  Future<void> pruneOlderThan(int beforeMs) async {
    final database = await _db.database;
    await database.delete(
      'habit_events',
      where: 'recorded_at < ?',
      whereArgs: [beforeMs],
    );
  }

  HabitEvent _fromRow(Map<String, Object?> row) {
    return HabitEvent(
      id: row['id'] as int?,
      facilityId: row['facility_id'] as String,
      recordedAt: row['recorded_at'] as int,
      actionType: HabitActionType.values.firstWhere(
        (t) => t.storageKey == row['action_type'],
        orElse: () => HabitActionType.view,
      ),
      weight: (row['weight'] as num?)?.toDouble() ?? HabitActionType.view.weight,
      dayOfWeek: row['day_of_week'] as int,
      hourOfDay: row['hour_of_day'] as int,
      timeBucket: row['time_bucket'] as String,
      swimStartTime: row['swim_start_time'] as String?,
    );
  }
}
