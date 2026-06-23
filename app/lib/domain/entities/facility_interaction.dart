/// Per-facility user interaction metrics persisted locally.
class FacilityInteractionMetrics {
  const FacilityInteractionMetrics({
    required this.facilityId,
    this.viewCount = 0,
    this.lastViewedAt,
    this.savedCount = 0,
    this.swimDetailClicks = 0,
    this.impressionCount = 0,
    this.ignoreCount = 0,
    this.lastIgnoredAt,
  });

  final String facilityId;
  final int viewCount;
  final int? lastViewedAt;
  final int savedCount;
  final int swimDetailClicks;
  final int impressionCount;
  final int ignoreCount;
  final int? lastIgnoredAt;

  bool get hasEngaged => viewCount > 0 || swimDetailClicks > 0 || savedCount > 0;

  int get passiveIgnoreSignal {
    if (viewCount > 0) return 0;
    final excess = impressionCount - 3;
    return excess > 0 ? excess : 0;
  }
}
