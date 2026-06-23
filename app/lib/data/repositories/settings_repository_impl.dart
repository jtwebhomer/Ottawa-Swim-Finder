import 'package:sqflite/sqflite.dart';

import '../../domain/repositories/repositories.dart';
import '../database/app_database.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl(this._db);

  final AppDatabase _db;

  @override
  Future<String?> getString(String key) async {
    final database = await _db.database;
    final rows = await database.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  @override
  Future<void> setString(String key, String value) async {
    final database = await _db.database;
    await database.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final value = await getString(key);
    if (value == null) return defaultValue;
    return value == 'true';
  }

  @override
  Future<void> setBool(String key, bool value) async {
    await setString(key, value.toString());
  }

  @override
  Future<int> getLastSyncAt() async {
    final value = await getString('last_sync_at');
    return int.tryParse(value ?? '') ?? 0;
  }

  @override
  Future<void> setLastSyncAt(int timestamp) async {
    await setString('last_sync_at', timestamp.toString());
  }
}
