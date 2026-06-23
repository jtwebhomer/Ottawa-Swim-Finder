/// Explicit failure classification for per-facility sync diagnostics.
enum FacilitySyncFailureKind {
  ok('OK'),
  unchanged('UNCHANGED'),
  blockedBotChallenge('BLOCKED'),
  blockedPlaywright('BLOCKED_PLAYWRIGHT'),
  parseEmpty('PARSE_EMPTY'),
  parseRejected('PARSE_REJECTED'),
  networkFailure('NETWORK_FAILURE'),
  pipelineCrash('PIPELINE_CRASH'),
  cachedFallback('CACHED_FALLBACK');

  const FacilitySyncFailureKind(this.label);
  final String label;

  bool get isSystemFailure =>
      this == networkFailure || this == pipelineCrash;

  bool get isBlocked => this == blockedBotChallenge;

  bool get isParseIssue =>
      this == parseEmpty || this == parseRejected;
}

/// Per-facility sync diagnostic record (logged + shown in Diagnostics).
class FacilitySyncDiagnostic {
  const FacilitySyncDiagnostic({
    required this.facilityId,
    required this.facilityName,
    required this.kind,
    this.httpStatus,
    this.requestUrl,
    this.finalUrl,
    this.contentType,
    this.blockedCheckSummary,
    this.htmlFingerprint,
    this.sessionsParsed = 0,
    this.swimMentions = 0,
    this.existingCachedSessions = 0,
    this.detail,
    this.fetchTier,
    this.tierTrail,
    this.domSizeBytes,
    this.loadTimeMs,
    this.syncEngine,
    this.scheduleTableCount,
    this.usedHttpFallback = false,
  });

  final String facilityId;
  final String facilityName;
  final FacilitySyncFailureKind kind;
  final int? httpStatus;
  final String? requestUrl;
  final String? finalUrl;
  final String? contentType;
  final String? blockedCheckSummary;
  final String? htmlFingerprint;
  final int sessionsParsed;
  final int swimMentions;
  final int existingCachedSessions;
  final String? detail;
  final String? fetchTier;
  final String? tierTrail;
  final int? domSizeBytes;
  final int? loadTimeMs;
  final String? syncEngine;
  final int? scheduleTableCount;
  final bool usedHttpFallback;

  String get statusLabel => kind.label;

  String debugLine() {
    final http = httpStatus?.toString() ?? '—';
    return 'Facility: $facilityName\n'
        'Status: $statusLabel\n'
        'HTTP: $http\n'
        'Fetch tier: ${fetchTier ?? '—'}\n'
        'Sync engine: ${syncEngine ?? '—'}\n'
        'Sessions parsed: $sessionsParsed\n'
        'Schedule tables: ${scheduleTableCount ?? '—'}\n'
        'DOM size: ${domSizeBytes ?? '—'}\n'
        'Load time: ${loadTimeMs != null ? '${loadTimeMs}ms' : '—'}\n'
        'HTTP fallback: ${usedHttpFallback ? 'yes' : 'no'}\n'
        'HTML fingerprint: ${htmlFingerprint ?? '—'}\n'
        'Blocked check: ${blockedCheckSummary ?? '—'}\n'
        'Cached sessions kept: $existingCachedSessions'
        '${tierTrail != null ? '\nTier trail: $tierTrail' : ''}'
        '${detail != null ? '\nDetail: $detail' : ''}';
  }

  String logMessage() =>
      '[$statusLabel] $facilityId http=$httpStatus tier=${fetchTier ?? 'n/a'} '
      'engine=${syncEngine ?? 'n/a'} '
      'parsed=$sessionsParsed tables=${scheduleTableCount ?? 'n/a'} '
      'dom=${domSizeBytes ?? 'n/a'} ${loadTimeMs ?? 0}ms '
      'fallback=$usedHttpFallback '
      'fingerprint=${htmlFingerprint ?? 'n/a'} '
      'blocked=${blockedCheckSummary ?? 'n/a'} '
      'cached=$existingCachedSessions'
      '${detail != null ? ' $detail' : ''}';
}
