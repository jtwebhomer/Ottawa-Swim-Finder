import '../../core/constants/app_constants.dart';
import '../../core/constants/sync_rate_limit_policy.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/schedule_trust_status.dart';
import '../../domain/entities/sync_status.dart';
import '../../domain/repositories/repositories.dart';

/// Resolves display trust status and aggregates for Home / diagnostics.
class ScheduleTrustResolver {
  ScheduleTrustResolver({SettingsRepository? settingsRepo})
      : _settingsRepo = settingsRepo;

  final SettingsRepository? _settingsRepo;

  Future<int> staleThresholdHours() async {
    if (_settingsRepo == null) {
      return SyncRateLimitPolicy.defaultStaleThresholdHours;
    }
    final raw = await _settingsRepo!.getString(
      AppConstants.settingsStaleThresholdHours,
    );
    return int.tryParse(raw ?? '') ??
        SyncRateLimitPolicy.defaultStaleThresholdHours;
  }

  /// Effective trust for UI, applying stale threshold to verified facilities.
  ScheduleTrustStatus resolve({
    required Facility facility,
    required int scheduleCount,
    required int staleThresholdHours,
    bool syncBlocked = false,
  }) {
    if (!facility.hasSwimSchedule) {
      return ScheduleTrustStatus.unverified;
    }

    if (scheduleCount == 0) {
      return ScheduleTrustStatus.unverified;
    }

    final stored = facility.scheduleTrustStatus;
    final now = DateTime.now().millisecondsSinceEpoch;
    final staleBefore =
        now - Duration(hours: staleThresholdHours).inMilliseconds;

    if (stored == ScheduleTrustStatus.verified) {
      final verifiedAt = facility.scheduleVerifiedAt;
      if (verifiedAt != null && verifiedAt < staleBefore) {
        return ScheduleTrustStatus.stale;
      }
      if (syncBlocked) {
        return ScheduleTrustStatus.cached;
      }
      return ScheduleTrustStatus.verified;
    }

    if (stored == ScheduleTrustStatus.fixture) {
      return ScheduleTrustStatus.fixture;
    }

    if (stored == ScheduleTrustStatus.cached) {
      return ScheduleTrustStatus.cached;
    }

    if (stored == ScheduleTrustStatus.stale) {
      return ScheduleTrustStatus.stale;
    }

    return ScheduleTrustStatus.unverified;
  }

  ScheduleTrustSummary summarize({
    required List<Facility> facilities,
    required Map<String, int> sessionCounts,
    required int staleThresholdHours,
    bool syncBlocked = false,
  }) {
    var verified = 0;
    var fixture = 0;
    var cached = 0;
    var stale = 0;
    var unverified = 0;

    for (final facility in facilities) {
      if (!facility.hasSwimSchedule) continue;
      final count = sessionCounts[facility.id] ?? 0;
      final trust = resolve(
        facility: facility,
        scheduleCount: count,
        staleThresholdHours: staleThresholdHours,
        syncBlocked: syncBlocked,
      );
      switch (trust) {
        case ScheduleTrustStatus.verified:
          verified++;
        case ScheduleTrustStatus.fixture:
          fixture++;
        case ScheduleTrustStatus.cached:
          cached++;
        case ScheduleTrustStatus.stale:
          stale++;
        case ScheduleTrustStatus.unverified:
          unverified++;
      }
    }

    return ScheduleTrustSummary(
      verified: verified,
      fixture: fixture,
      cached: cached,
      stale: stale,
      unverified: unverified,
    );
  }
}

class ScheduleTrustSummary {
  const ScheduleTrustSummary({
    required this.verified,
    required this.fixture,
    required this.cached,
    required this.stale,
    required this.unverified,
  });

  final int verified;
  final int fixture;
  final int cached;
  final int stale;
  final int unverified;

  int get withSchedules => verified + fixture + cached + stale;
}
