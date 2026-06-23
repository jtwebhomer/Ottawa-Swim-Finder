/// Which tier produced a successful facility page fetch.
enum FacilityFetchTier {
  http('HTTP'),
  browser('BROWSER'),
  cacheSnapshot('CACHE_SNAPSHOT'),
  cacheDb('CACHE_DB');

  const FacilityFetchTier(this.label);
  final String label;
}

/// HTML page returned by a fetch tier.
class FacilityPageFetchResult {
  const FacilityPageFetchResult({
    required this.html,
    required this.statusCode,
    required this.finalUrl,
    required this.tier,
    this.contentType,
    this.domSizeBytes,
    this.loadTimeMs,
    this.scheduleTableCount,
    this.syncEngineLabel,
    this.usedHttpFallback = false,
  });

  final String html;
  final int statusCode;
  final String finalUrl;
  final String? contentType;
  final FacilityFetchTier tier;
  final int? domSizeBytes;
  final int? loadTimeMs;
  final int? scheduleTableCount;
  final String? syncEngineLabel;
  final bool usedHttpFallback;
}

/// Record of each tier attempted during resilient fetch.
class FetchTierAttempt {
  const FetchTierAttempt({
    required this.tier,
    required this.outcome,
    this.httpStatus,
    this.detail,
  });

  final FacilityFetchTier tier;
  final String outcome;
  final int? httpStatus;
  final String? detail;

  @override
  String toString() =>
      '${tier.label}:$outcome${httpStatus != null ? '@$httpStatus' : ''}'
      '${detail != null ? ' ($detail)' : ''}';
}
