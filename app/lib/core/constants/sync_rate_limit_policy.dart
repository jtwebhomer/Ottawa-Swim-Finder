/// Rate-limit-safe sync defaults for ottawa.ca fetches.
class SyncRateLimitPolicy {
  const SyncRateLimitPolicy._();

  /// Minimum delay between sequential HTTP requests.
  static const int minInterRequestDelayMs = 300;

  /// Maximum delay between sequential HTTP requests (jitter applied).
  static const int maxInterRequestDelayMs = 1200;

  /// Default facility cache freshness before a network refresh is considered.
  static const int defaultStaleThresholdHours = 48;

  static const int minStaleThresholdHours = 24;
  static const int maxStaleThresholdHours = 72;

  /// Phase 1 — immediate high-value facilities on app open.
  static const int phase1FacilityCount = 5;
  static const int phase1MinFacilityCount = 3;

  /// Phase 2 — expand nearby / priority coverage.
  static const int phase2FacilityCount = 8;

  /// Phase 3 — idle background stale rotation.
  static const int phase3FacilityCount = 6;

  /// Facilities refreshed per routine background / startup sync (legacy alias).
  static const int facilitiesPerPartialSync = phase3FacilityCount;

  /// Larger batch for first-time onboarding (still throttled, not a burst).
  static const int onboardingFacilitiesPerSync = 8;

  /// Skip live catalog discovery if synced within this window.
  static const int catalogRefreshIntervalHours = 24;

  /// Per-facility exponential backoff after bot-block detection.
  static const List<Duration> blockBackoffSteps = [
    Duration(minutes: 30),
    Duration(hours: 6),
    Duration(hours: 24),
  ];

  static Duration backoffForBlockCount(int blockCount) {
    if (blockCount <= 0) return Duration.zero;
    final index = (blockCount - 1).clamp(0, blockBackoffSteps.length - 1);
    return blockBackoffSteps[index];
  }
}
