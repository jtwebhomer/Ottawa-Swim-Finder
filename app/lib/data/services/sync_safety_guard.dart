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
  /// Minimum entries expected when HTML clearly contains swim schedules.
  static const int minEntriesWhenHtmlHasSwims = 1;

  SyncWriteDecision evaluate({
    required String facilityId,
    required List<ScheduleEntry> newEntries,
    required int existingEntryCount,
    required int htmlSwimMentions,
    required int httpStatus,
  }) {
    if (httpStatus != 200) {
      return SyncWriteDecision.reject('HTTP $httpStatus — keeping $existingEntryCount cached rows');
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

  /// Whether a full sync run should be considered successful overall.
  bool isSyncHealthy({
    required int totalFacilities,
    required int updated,
    required int skipped,
    required int errors,
    required int scheduleCountAfter,
    required int scheduleCountBefore,
  }) {
    if (errors == 0) return true;
    // Partial success is OK if we didn't lose data.
    if (scheduleCountAfter >= scheduleCountBefore && scheduleCountAfter > 0) {
      return true;
    }
    if (updated > 0 && scheduleCountAfter > 0) return true;
    // All failed but we still have cached data.
    if (errors < totalFacilities && scheduleCountAfter > 0) return true;
    return false;
  }
}
