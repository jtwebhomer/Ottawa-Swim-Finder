import 'package:sqflite/sqflite.dart';

import '../../core/constants/app_constants.dart';
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
    await setString('last_sync_success_at', timestamp.toString());
  }

  @override
  Future<int> getLastSyncAttemptAt() async {
    final value = await getString('last_sync_attempt_at');
    return int.tryParse(value ?? '') ?? 0;
  }

  @override
  Future<void> setLastSyncAttemptAt(int timestamp) async {
    await setString('last_sync_attempt_at', timestamp.toString());
  }

  @override
  Future<String?> getLastSyncStatus() async => getString('last_sync_status');

  @override
  Future<void> setLastSyncStatus(String status) async {
    await setString('last_sync_status', status);
  }

  @override
  Future<bool> isOnboardingComplete() async =>
      getBool('onboarding_complete', defaultValue: false);

  @override
  Future<void> setOnboardingComplete(bool complete) async {
    await setBool('onboarding_complete', complete);
  }

  @override
  Future<String?> getLastSyncedAppVersion() async =>
      getString(AppConstants.settingsLastSyncedAppVersion);

  @override
  Future<void> setLastSyncedAppVersion(String version) async {
    await setString(AppConstants.settingsLastSyncedAppVersion, version);
  }
}
