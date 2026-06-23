import 'dart:convert';

import '../../core/constants/sync_rate_limit_policy.dart';
import '../../domain/repositories/repositories.dart';

/// Persists per-facility bot-block backoff so we do not hammer ottawa.ca.
class FacilityBackoffTracker {
  FacilityBackoffTracker(this._settingsRepo);

  static const _settingsKey = 'facility_backoff_state';

  final SettingsRepository _settingsRepo;
  Map<String, _BackoffEntry>? _cache;

  Future<bool> isInBackoff(String facilityId, {DateTime? now}) async {
    final entry = (await _load())[facilityId];
    if (entry == null) return false;
    final clock = now ?? DateTime.now();
    return clock.isBefore(entry.retryAfter);
  }

  Future<DateTime?> retryAfter(String facilityId) async {
    final entry = (await _load())[facilityId];
    return entry?.retryAfter;
  }

  Future<int> blockCount(String facilityId) async {
    return (await _load())[facilityId]?.blockCount ?? 0;
  }

  Future<void> recordBlock(String facilityId, {DateTime? now}) async {
    final state = await _load();
    final clock = now ?? DateTime.now();
    final previous = state[facilityId];
    final nextCount = (previous?.blockCount ?? 0) + 1;
    final delay = SyncRateLimitPolicy.backoffForBlockCount(nextCount);
    state[facilityId] = _BackoffEntry(
      blockCount: nextCount,
      retryAfter: clock.add(delay),
      lastBlockedAt: clock,
    );
    await _persist(state);
  }

  Future<void> recordSuccess(String facilityId) async {
    final state = await _load();
    if (state.remove(facilityId) != null) {
      await _persist(state);
    }
  }

  Future<Map<String, _BackoffEntry>> _load() async {
    if (_cache != null) return _cache!;
    final raw = await _settingsRepo.getString(_settingsKey);
    if (raw == null || raw.isEmpty) {
      _cache = {};
      return _cache!;
    }
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      _cache = decoded.map(
        (id, value) => MapEntry(
          id,
          _BackoffEntry.fromJson(value as Map<String, dynamic>),
        ),
      );
    } catch (_) {
      _cache = {};
    }
    return _cache!;
  }

  Future<void> _persist(Map<String, _BackoffEntry> state) async {
    _cache = Map.from(state);
    final encoded = json.encode(
      state.map((id, entry) => MapEntry(id, entry.toJson())),
    );
    await _settingsRepo.setString(_settingsKey, encoded);
  }
}

class _BackoffEntry {
  const _BackoffEntry({
    required this.blockCount,
    required this.retryAfter,
    required this.lastBlockedAt,
  });

  final int blockCount;
  final DateTime retryAfter;
  final DateTime lastBlockedAt;

  factory _BackoffEntry.fromJson(Map<String, dynamic> json) {
    return _BackoffEntry(
      blockCount: json['blockCount'] as int? ?? 1,
      retryAfter: DateTime.fromMillisecondsSinceEpoch(
        json['retryAfterMs'] as int? ?? 0,
      ),
      lastBlockedAt: DateTime.fromMillisecondsSinceEpoch(
        json['lastBlockedAtMs'] as int? ?? 0,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'blockCount': blockCount,
        'retryAfterMs': retryAfter.millisecondsSinceEpoch,
        'lastBlockedAtMs': lastBlockedAt.millisecondsSinceEpoch,
      };
}
