import 'package:flutter_test/flutter_test.dart';
import 'package:ottawa_swim_finder/core/constants/sync_rate_limit_policy.dart';
import 'package:ottawa_swim_finder/data/services/facility_backoff_tracker.dart';
import 'package:ottawa_swim_finder/data/services/partial_refresh_planner.dart';
import 'package:ottawa_swim_finder/domain/entities/facility.dart';
import 'package:ottawa_swim_finder/domain/entities/facility_type.dart';
import 'package:ottawa_swim_finder/domain/entities/sync_status.dart';
import 'package:ottawa_swim_finder/domain/repositories/repositories.dart';

class _MemorySettingsRepo implements SettingsRepository {
  final Map<String, String> _values = {};

  @override
  Future<String?> getString(String key) async => _values[key];

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<bool> getBool(String key, {bool defaultValue = false}) async =>
      _values[key] == 'true';

  @override
  Future<void> setBool(String key, bool value) async {
    _values[key] = value.toString();
  }

  @override
  Future<int> getLastSyncAt() async => 0;

  @override
  Future<void> setLastSyncAt(int timestamp) async {}

  @override
  Future<int> getLastSyncAttemptAt() async => 0;

  @override
  Future<void> setLastSyncAttemptAt(int timestamp) async {}

  @override
  Future<String?> getLastSyncStatus() async => null;

  @override
  Future<void> setLastSyncStatus(String status) async {}

  @override
  Future<bool> isOnboardingComplete() async => false;

  @override
  Future<void> setOnboardingComplete(bool complete) async {}

  @override
  Future<String?> getLastSyncedAppVersion() async => null;

  @override
  Future<void> setLastSyncedAppVersion(String version) async {}
}

Facility _facility({
  required String id,
  bool favorite = false,
  FacilitySyncStatus status = FacilitySyncStatus.ok,
  int? lastSuccessfulSyncAt,
}) {
  return Facility(
    id: id,
    name: id,
    lastSuccessfulSyncAt: lastSuccessfulSyncAt,
    syncStatus: status,
    isFavorite: favorite,
  );
}

void main() {
  group('PartialRefreshPlanner', () {
    const planner = PartialRefreshPlanner();
    final now = DateTime(2026, 6, 22, 12);

    test('skips fresh facilities during routine sync', () {
      final freshAt =
          now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch;
      final selected = planner.selectFacilitiesForRefresh(
        facilities: [
          _facility(id: 'a', lastSuccessfulSyncAt: freshAt),
          _facility(id: 'b', lastSuccessfulSyncAt: freshAt),
        ],
        force: false,
        isOnboarding: false,
        staleThresholdHours: 48,
        rotationIndex: 0,
        now: now,
      );
      expect(selected, isEmpty);
    });

    test('prioritizes favorites and oldest stale data', () {
      final old =
          now.subtract(const Duration(hours: 80)).millisecondsSinceEpoch;
      final selected = planner.selectFacilitiesForRefresh(
        facilities: [
          _facility(id: 'old', lastSuccessfulSyncAt: old),
          _facility(id: 'fav', favorite: true, lastSuccessfulSyncAt: old),
        ],
        force: false,
        isOnboarding: false,
        staleThresholdHours: 48,
        rotationIndex: 0,
        now: now,
      );
      expect(selected.first.id, 'fav');
    });

    test('caps batch size for routine sync', () {
      final old =
          now.subtract(const Duration(hours: 80)).millisecondsSinceEpoch;
      final facilities = List.generate(
        12,
        (i) => _facility(id: 'f$i', lastSuccessfulSyncAt: old),
      );
      final selected = planner.selectFacilitiesForRefresh(
        facilities: facilities,
        force: false,
        isOnboarding: false,
        staleThresholdHours: 48,
        rotationIndex: 0,
        now: now,
      );
      expect(
        selected.length,
        SyncRateLimitPolicy.facilitiesPerPartialSync,
      );
    });
  });

  group('FacilityBackoffTracker', () {
    test('applies 30m / 6h / 24h backoff steps', () async {
      final repo = _MemorySettingsRepo();
      final tracker = FacilityBackoffTracker(repo);
      final start = DateTime(2026, 6, 22, 12);

      await tracker.recordBlock('pool-a', now: start);
      expect(
        await tracker.retryAfter('pool-a'),
        start.add(const Duration(minutes: 30)),
      );

      await tracker.recordBlock('pool-a', now: start.add(const Duration(hours: 1)));
      expect(
        await tracker.retryAfter('pool-a'),
        start.add(const Duration(hours: 7)),
      );

      await tracker.recordBlock('pool-a', now: start.add(const Duration(hours: 8)));
      expect(
        await tracker.retryAfter('pool-a'),
        start.add(const Duration(hours: 32)),
      );

      await tracker.recordSuccess('pool-a');
      expect(await tracker.isInBackoff('pool-a'), isFalse);
    });
  });

  group('SyncStatus rate-limit rules', () {
    test('network failures with cache are partial not failed', () {
      final status = SyncStatus.fromCounts(
        totalFacilities: 20,
        updated: 0,
        skipped: 10,
        blocked: 0,
        parseEmpty: 0,
        parseRejected: 0,
        networkFailures: 3,
        pipelineCrashes: 0,
        antiCorruptionTriggered: false,
        scheduleCountAfter: 400,
      );
      expect(status, SyncStatus.partialSuccess);
    });
  });
}
