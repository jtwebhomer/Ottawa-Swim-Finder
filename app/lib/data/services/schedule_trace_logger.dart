import '../../core/logging/app_logger.dart';
import '../../domain/entities/schedule_entry.dart';

/// End-to-end trace logging for a single facility scrape/parse cycle.
class ScheduleTraceLogger {
  void logParseStart({
    required String facilityId,
    required int htmlLength,
    String? snapshotPath,
  }) {
    appLogger.i(
      '[schedule-trace] parse start facility=$facilityId htmlBytes=$htmlLength '
      'snapshot=${snapshotPath ?? 'none'}',
    );
  }

  void logParsedEntries({
    required String facilityId,
    required List<ScheduleEntry> entries,
    required String today,
  }) {
    final todayEntries =
        entries.where((e) => e.date == today).toList(growable: false);
    final sample = todayEntries.take(5).map(_formatEntry).join('; ');
    appLogger.i(
      '[schedule-trace] parsed facility=$facilityId total=${entries.length} '
      'today=${todayEntries.length} sampleToday=[$sample]',
    );
  }

  void logStoredEntries({
    required String facilityId,
    required int storedCount,
    required int todayCount,
  }) {
    appLogger.i(
      '[schedule-trace] stored facility=$facilityId rows=$storedCount today=$todayCount',
    );
  }

  void logUiDataset({
    required String today,
    required int timelineCount,
    required int activeCount,
    required int facilitiesWithToday,
  }) {
    appLogger.i(
      '[schedule-trace] ui today=$today timeline=$timelineCount active=$activeCount '
      'facilitiesWithSwims=$facilitiesWithToday',
    );
  }

  void logDroppedTimeCell({
    required String facilityId,
    required String rawCategory,
    required String cellText,
    required String reason,
  }) {
    appLogger.w(
      '[schedule-trace] dropped-time facility=$facilityId category=$rawCategory '
      'cell="$cellText" reason=$reason',
    );
  }

  String _formatEntry(ScheduleEntry e) =>
      '${e.category} ${e.startTime}-${e.endTime}';
}
