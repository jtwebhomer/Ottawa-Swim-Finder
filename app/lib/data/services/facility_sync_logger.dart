import '../../core/logging/app_logger.dart';
import '../../domain/entities/facility_sync_diagnostic.dart';

/// Structured per-facility sync logging for diagnosis.
class FacilitySyncLogger {
  final List<FacilitySyncDiagnostic> lastRunDiagnostics = [];

  void clear() => lastRunDiagnostics.clear();

  void record(FacilitySyncDiagnostic diagnostic) {
    lastRunDiagnostics.add(diagnostic);
    appLogger.i('[facility-sync]\n${diagnostic.debugLine()}');
  }

  void logRunSummary({
    required int total,
    required int updated,
    required int blocked,
    required int parseEmpty,
    required int systemFailures,
  }) {
    appLogger.i(
      '[facility-sync] SUMMARY total=$total updated=$updated '
      'blocked=$blocked parseEmpty=$parseEmpty systemFailures=$systemFailures',
    );
    for (final d in lastRunDiagnostics) {
      if (d.kind != FacilitySyncFailureKind.ok &&
          d.kind != FacilitySyncFailureKind.unchanged) {
        appLogger.w('[facility-sync] ${d.logMessage()}');
      }
    }
  }

  List<FacilitySyncDiagnostic> blockedFacilities() => lastRunDiagnostics
      .where((d) => d.kind == FacilitySyncFailureKind.blockedBotChallenge)
      .toList();

  List<FacilitySyncDiagnostic> parseEmptyFacilities() => lastRunDiagnostics
      .where((d) => d.kind == FacilitySyncFailureKind.parseEmpty)
      .toList();

  List<FacilitySyncDiagnostic> systemFailureFacilities() =>
      lastRunDiagnostics.where((d) => d.kind.isSystemFailure).toList();
}
