import '../../core/constants/app_constants.dart';
import '../../domain/repositories/repositories.dart';

/// Persisted sync health metrics for debug / settings UI.
class SyncHealthSnapshot {
  const SyncHealthSnapshot({
    this.lastSyncAt,
    this.lastSuccessfulSyncAt,
    this.lastFullyCleanSyncAt,
    this.lastSyncStatus,
    this.lastScheduleCountBefore,
    this.lastScheduleCountAfter,
    this.lastUpdatedFacilities,
    this.lastSkippedFacilities,
    this.lastErrorCount,
    this.lastBlockedCount,
    this.lastStaleCount,
    this.lastSuccessRate,
    this.lastHttp403Count,
    this.lastSyncDurationMs,
    this.lastSyncedAppVersion,
  });

  final DateTime? lastSyncAt;
  final DateTime? lastSuccessfulSyncAt;
  final DateTime? lastFullyCleanSyncAt;
  final String? lastSyncStatus;
  final int? lastScheduleCountBefore;
  final int? lastScheduleCountAfter;
  final int? lastUpdatedFacilities;
  final int? lastSkippedFacilities;
  final int? lastErrorCount;
  final int? lastBlockedCount;
  final int? lastStaleCount;
  final double? lastSuccessRate;
  final int? lastHttp403Count;
  final int? lastSyncDurationMs;
  final String? lastSyncedAppVersion;

  bool get hasData =>
      lastScheduleCountAfter != null && lastScheduleCountAfter! > 0;

  bool get isPartialSuccess => lastSyncStatus == 'PARTIAL_SUCCESS';
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
    required int blocked,
    required int staleCount,
    required double successRate,
    required int http403Count,
    required int durationMs,
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
    await _settings.setString('${_prefix}blocked', blocked.toString());
    await _settings.setString('${_prefix}stale', staleCount.toString());
    await _settings.setString(
      '${_prefix}success_rate',
      successRate.toStringAsFixed(3),
    );
    await _settings.setString('${_prefix}http_403', http403Count.toString());
    await _settings.setString('${_prefix}duration_ms', durationMs.toString());

    if (status == 'SUCCESS' || status == 'PARTIAL_SUCCESS') {
      await _settings.setString('${_prefix}last_success_at', now.toString());
    }
    if (status == 'SUCCESS') {
      await _settings.setString('${_prefix}last_fully_clean_at', now.toString());
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

    Future<double?> readDouble(String key) async {
      final raw = await _settings.getString('$_prefix$key');
      return double.tryParse(raw ?? '');
    }

    return SyncHealthSnapshot(
      lastSyncAt: await readTimestamp('last_sync_at'),
      lastSuccessfulSyncAt: await readTimestamp('last_success_at'),
      lastFullyCleanSyncAt: await readTimestamp('last_fully_clean_at'),
      lastSyncStatus: await _settings.getString('${_prefix}last_sync_status'),
      lastScheduleCountBefore: await readInt('schedule_count_before'),
      lastScheduleCountAfter: await readInt('schedule_count_after'),
      lastUpdatedFacilities: await readInt('updated'),
      lastSkippedFacilities: await readInt('skipped'),
      lastErrorCount: await readInt('errors'),
      lastBlockedCount: await readInt('blocked'),
      lastStaleCount: await readInt('stale'),
      lastSuccessRate: await readDouble('success_rate'),
      lastHttp403Count: await readInt('http_403'),
      lastSyncDurationMs: await readInt('duration_ms'),
      lastSyncedAppVersion:
          await _settings.getString(AppConstants.settingsLastSyncedAppVersion),
    );
  }
}
