import '../../domain/entities/facility.dart';
import '../../domain/entities/facility_type.dart';
import '../../domain/entities/schedule_trust_status.dart';
import '../../domain/entities/sync_status.dart';

/// Resolves browse UI status labels for facilities.
class FacilityBrowseHelper {
  static FacilityBrowseStatus statusFor({
    required Facility facility,
    required int sessionCount,
    required int todaySessionCount,
    ScheduleTrustStatus? trustStatus,
  }) {
    final trust = trustStatus ?? facility.scheduleTrustStatus;

    if (trust == ScheduleTrustStatus.stale ||
        trust == ScheduleTrustStatus.cached ||
        facility.syncStatus == FacilitySyncStatus.stale ||
        facility.displayStatus == FacilityDisplayStatus.stale) {
      return FacilityBrowseStatus.stale;
    }

    if (facility.displayStatus == FacilityDisplayStatus.blocked) {
      return FacilityBrowseStatus.parseIssue;
    }

    return switch (facility.dataModel) {
      FacilityDataModel.hoursOnly => FacilityBrowseStatus.hoursOnly,
      FacilityDataModel.statusOnly => FacilityBrowseStatus.statusOnly,
      FacilityDataModel.mixedSeasonal || FacilityDataModel.seasonalHours =>
        FacilityBrowseStatus.seasonal,
      FacilityDataModel.swimSchedule => _swimScheduleStatus(
          facility: facility,
          sessionCount: sessionCount,
          todaySessionCount: todaySessionCount,
        ),
    };
  }

  static FacilityBrowseStatus _swimScheduleStatus({
    required Facility facility,
    required int sessionCount,
    required int todaySessionCount,
  }) {
    if (facility.displayStatus == FacilityDisplayStatus.parseIssue) {
      return FacilityBrowseStatus.parseIssue;
    }
    if (todaySessionCount > 0 || sessionCount > 0) {
      return FacilityBrowseStatus.open;
    }
    if (facility.displayStatus == FacilityDisplayStatus.liveOk) {
      return FacilityBrowseStatus.open;
    }
    return FacilityBrowseStatus.parseIssue;
  }

  static String trustLabelFor(ScheduleTrustStatus trust) => trust.label;

  static String subtitleFor({
    required Facility facility,
    required FacilityBrowseStatus status,
    required int sessionCount,
    ScheduleTrustStatus? trustStatus,
  }) {
    final parts = <String>[
      facility.facilityType.label,
      facility.dataModel.label,
    ];

    if (facility.dataModel.expectsSwimTable && sessionCount > 0) {
      parts.add('$sessionCount swims');
    }

    parts.add(status.label);

    final trust = trustStatus ?? facility.scheduleTrustStatus;
    if (facility.dataModel.expectsSwimTable && sessionCount > 0) {
      parts.add(trust.label);
    }

    return parts.join(' · ');
  }
}
