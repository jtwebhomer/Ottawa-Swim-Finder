/// Configurable thresholds for sync anomaly detection.
class SyncThresholds {
  const SyncThresholds._();

  /// Minimum total sessions before global ratio checks apply.
  static const int minBaselineSessionCount = 200;

  /// Reject full sync if projected total falls below this ratio of baseline.
  static const double minGlobalSessionRatio = 0.35;

  /// Reject per-facility write if new count falls below this ratio.
  static const double minFacilitySessionRatio = 0.25;

  /// Minimum existing rows before per-facility ratio check applies.
  static const int minFacilityBaselineRows = 15;

  /// Future sessions must be at least this ratio of baseline future count.
  static const double minFutureSessionRatio = 0.35;

  /// Minimum fraction of facilities that must succeed before any commits apply.
  static const double minGlobalSuccessRate = 0.60;

  static const int minFutureBaseline = 100;
}
