/// Overall result of a sync run.
enum SyncStatus {
  success,
  partialSuccess,
  failed;

  String get label => switch (this) {
        SyncStatus.success => 'SUCCESS',
        SyncStatus.partialSuccess => 'PARTIAL_SUCCESS',
        SyncStatus.failed => 'FAILED',
      };

  static SyncStatus fromCounts({
    required int totalFacilities,
    required int updated,
    required int skipped,
    required int blocked,
    required int parseEmpty,
    required int parseRejected,
    required int networkFailures,
    required int pipelineCrashes,
    required bool antiCorruptionTriggered,
    required int scheduleCountAfter,
  }) {
    if (antiCorruptionTriggered) return SyncStatus.failed;

    final systemFailures = networkFailures + pipelineCrashes;
    final hasCachedData = scheduleCountAfter > 0;
    final anySuccess = updated > 0 || skipped > 0;

    // Rate limits / bot blocks alone never constitute a full sync failure.
    if (!hasCachedData &&
        !anySuccess &&
        blocked > 0 &&
        systemFailures == 0 &&
        parseEmpty == 0 &&
        parseRejected == 0) {
      return SyncStatus.failed;
    }

    if (!hasCachedData && !anySuccess && systemFailures > 0) {
      return SyncStatus.failed;
    }

    if (!hasCachedData && !anySuccess) {
      return SyncStatus.failed;
    }

    if (systemFailures == 0 &&
        (blocked > 0 || parseEmpty > 0 || parseRejected > 0)) {
      return SyncStatus.partialSuccess;
    }

    if (systemFailures > 0 && (anySuccess || hasCachedData)) {
      return SyncStatus.partialSuccess;
    }

    if (systemFailures > 0) return SyncStatus.partialSuccess;

    return SyncStatus.success;
  }
}

/// Per-facility freshness after a sync attempt.
enum FacilitySyncStatus {
  ok('OK'),
  stale('STALE'),
  failed('FAILED');

  const FacilitySyncStatus(this.label);
  final String label;

  static FacilitySyncStatus? fromDb(String? value) {
    if (value == null) return null;
    return FacilitySyncStatus.values.firstWhere(
      (s) => s.label == value,
      orElse: () => FacilitySyncStatus.ok,
    );
  }
}

/// Outcome of fetching a single facility page.
enum FacilityFetchOutcome {
  success,
  blocked,
  httpError,
  unchanged,
  parseEmpty,
  parseFailure,
  pipelineCrash,
  staleCached,
}

/// Validation classification for commit eligibility.
enum FacilityValidationClass {
  valid,
  partial,
  failed,
}
