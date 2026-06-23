import '../../domain/repositories/repositories.dart';

/// Persisted sync health metrics for debug / settings UI.
class SyncHealthSnapshot {
  const SyncHealthSnapshot({
    this.lastSyncAt,
    this.lastSuccessfulSyncAt,
    this.lastSyncStatus,
    this.lastScheduleCountBefore,
    this.lastScheduleCountAfter,
    this.lastUpdatedFacilities,
    this.lastSkippedFacilities,
    this.lastErrorCount,
    this.lastHttp403Count,
  });

  final DateTime? lastSyncAt;
  final DateTime? lastSuccessfulSyncAt;
  final String? lastSyncStatus;
  final int? lastScheduleCountBefore;
  final int? lastScheduleCountAfter;
  final int? lastUpdatedFacilities;
  final int? lastSkippedFacilities;
  final int? lastErrorCount;
  final int? lastHttp403Count;

  bool get hasData =>
      lastScheduleCountAfter != null && lastScheduleCountAfter! > 0;
}

class SyncHealthService {
  SyncHealthService(this._settings);

  final SettingsRepository _settings;

  static const _prefix = 'health_';

  Future<void> recordSyncResult({
    required String status,
    required int scheduleCountBefore,
    required int scheduleCountAfter,
    required int updated,
    required int skipped,
    required int errors,
    required int http403Count,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _settings.setString('${_prefix}last_sync_at', now.toString());
    await _settings.setString('${_prefix}last_sync_status', status);
    await _settings.setString(
      '${_prefix}schedule_count_before',
      scheduleCountBefore.toString(),
    );
    await _settings.setString(
      '${_prefix}schedule_count_after',
      scheduleCountAfter.toString(),
    );
    await _settings.setString('${_prefix}updated', updated.toString());
    await _settings.setString('${_prefix}skipped', skipped.toString());
    await _settings.setString('${_prefix}errors', errors.toString());
    await _settings.setString('${_prefix}http_403', http403Count.toString());

    if (status == 'success' || status == 'partial') {
      await _settings.setString('${_prefix}last_success_at', now.toString());
    }
  }

  Future<SyncHealthSnapshot> load() async {
    Future<DateTime?> readTimestamp(String key) async {
      final raw = await _settings.getString('$_prefix$key');
      final ms = int.tryParse(raw ?? '');
      return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    }

    Future<int?> readInt(String key) async {
      final raw = await _settings.getString('$_prefix$key');
      return int.tryParse(raw ?? '');
    }

    return SyncHealthSnapshot(
      lastSyncAt: await readTimestamp('last_sync_at'),
      lastSuccessfulSyncAt: await readTimestamp('last_success_at'),
      lastSyncStatus: await _settings.getString('${_prefix}last_sync_status'),
      lastScheduleCountBefore: await readInt('schedule_count_before'),
      lastScheduleCountAfter: await readInt('schedule_count_after'),
      lastUpdatedFacilities: await readInt('updated'),
      lastSkippedFacilities: await readInt('skipped'),
      lastErrorCount: await readInt('errors'),
      lastHttp403Count: await readInt('http_403'),
    );
  }
}
