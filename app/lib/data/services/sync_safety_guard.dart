import '../../core/constants/sync_thresholds.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/entities/schedule_entry.dart';

/// Result of validating whether a scrape may replace stored schedules.
class SyncWriteDecision {
  const SyncWriteDecision.allow(this.reason) : allowWrite = true;
  const SyncWriteDecision.reject(this.reason) : allowWrite = false;

  final bool allowWrite;
  final String reason;
}

/// Prevents destructive sync writes that would wipe good cached data.
class SyncSafetyGuard {
  static const int minEntriesWhenHtmlHasSwims = 1;

  SyncWriteDecision evaluate({
    required String facilityId,
    required List<ScheduleEntry> newEntries,
    required int existingEntryCount,
    required int htmlSwimMentions,
    required int httpStatus,
  }) {
    if (httpStatus != 200) {
      return SyncWriteDecision.reject(
        'HTTP $httpStatus — keeping $existingEntryCount cached rows',
      );
    }

    if (newEntries.isEmpty && existingEntryCount > 0) {
      appLogger.w(
        '[sync-safety] Rejecting empty write for $facilityId '
        '(preserving $existingEntryCount rows, htmlSwimMentions=$htmlSwimMentions)',
      );
      return SyncWriteDecision.reject(
        'Parsed 0 entries but $existingEntryCount cached — kept existing data',
      );
    }

    if (newEntries.isEmpty &&
        htmlSwimMentions >= 3 &&
        existingEntryCount == 0) {
      return SyncWriteDecision.reject(
        'HTML mentions swims ($htmlSwimMentions) but parser returned 0 — kept empty',
      );
    }

    if (existingEntryCount >= SyncThresholds.minFacilityBaselineRows &&
        newEntries.isNotEmpty &&
        newEntries.length <
            (existingEntryCount * SyncThresholds.minFacilitySessionRatio)
                .round()) {
      return SyncWriteDecision.reject(
        'Facility session drop ${existingEntryCount}→${newEntries.length} '
        'below ${(SyncThresholds.minFacilitySessionRatio * 100).round()}% threshold',
      );
    }

    for (final entry in newEntries) {
      if (entry.startTime.compareTo(entry.endTime) >= 0) {
        return SyncWriteDecision.reject(
          'Invalid time range ${entry.startTime}-${entry.endTime} for ${entry.rawCategory}',
        );
      }
    }

    return SyncWriteDecision.allow(
      newEntries.isEmpty
          ? 'No entries (facility may have no swim data)'
          : 'Replacing with ${newEntries.length} entries',
    );
  }

  /// Reject an entire sync when projected totals look like a broken parse.
  SyncWriteDecision evaluateGlobalSync({
    required int countBefore,
    required int projectedCountAfter,
    required int futureBefore,
    required int projectedFutureAfter,
    required int facilitiesParsed,
    required int totalFacilities,
  }) {
    if (countBefore >= SyncThresholds.minBaselineSessionCount &&
        projectedCountAfter <
            (countBefore * SyncThresholds.minGlobalSessionRatio).round()) {
      appLogger.w(
        '[sync-safety] Global reject: projected $projectedCountAfter vs '
        'baseline $countBefore',
      );
      return const SyncWriteDecision.reject(
        'Source schedule data appears incomplete. '
        'Using previously verified schedule data.',
      );
    }

    if (futureBefore >= SyncThresholds.minFutureBaseline &&
        projectedFutureAfter <
            (futureBefore * SyncThresholds.minFutureSessionRatio).round()) {
      appLogger.w(
        '[sync-safety] Future-session reject: projected $projectedFutureAfter '
        'vs baseline $futureBefore',
      );
      return const SyncWriteDecision.reject(
        'Future session count dropped sharply — kept verified cached data.',
      );
    }

    if (totalFacilities > 0 &&
        facilitiesParsed < (totalFacilities * 0.5).round() &&
        countBefore > 0) {
      return SyncWriteDecision.reject(
        'Fewer than half of facilities parsed ($facilitiesParsed/$totalFacilities)',
      );
    }

    return SyncWriteDecision.allow('Global sync within expected bounds');
  }

  bool isSyncHealthy({
    required int totalFacilities,
    required int updated,
    required int skipped,
    required int errors,
    required int scheduleCountAfter,
    required int scheduleCountBefore,
    int blocked = 0,
    int rejected = 0,
    bool globalRejected = false,
  }) {
    if (globalRejected) return false;

    // At least one facility received a fresh commit.
    if (updated > 0) return true;

    // Bot-block or deferred facilities with no live refresh — not a healthy sync.
    if (blocked > 0 && updated == 0) return false;

    if (errors == 0) {
      if (rejected > 0 && updated == 0) return false;
      return scheduleCountAfter > 0;
    }

    if (scheduleCountAfter >= scheduleCountBefore && scheduleCountAfter > 0) {
      return true;
    }
    if (errors < totalFacilities && scheduleCountAfter > 0) return true;
    return false;
  }
}
