import '../../domain/entities/facility.dart';
import '../../domain/entities/facility_type.dart';
import '../../domain/entities/sync_status.dart';

/// Resolves browse UI status labels for facilities.
class FacilityBrowseHelper {
  static FacilityBrowseStatus statusFor({
    required Facility facility,
    required int sessionCount,
    required int todaySessionCount,
  }) {
    if (facility.syncStatus == FacilitySyncStatus.stale) {
      return FacilityBrowseStatus.stale;
    }

    if (facility.isSeasonal) {
      return FacilityBrowseStatus.seasonal;
    }

    if (facility.hasSwimSchedule) {
      if (todaySessionCount > 0 || sessionCount > 0) {
        return FacilityBrowseStatus.open;
      }
      return FacilityBrowseStatus.noSchedule;
    }

    return FacilityBrowseStatus.open;
  }

  static String subtitleFor({
    required Facility facility,
    required FacilityBrowseStatus status,
    required int sessionCount,
  }) {
    final parts = <String>[
      facility.facilityType.label,
      facility.scheduleMode.label,
    ];

    if (facility.hasSwimSchedule && sessionCount > 0) {
      parts.add('$sessionCount swims');
    } else if (facility.isSeasonal) {
      parts.add('Seasonal hours');
    } else if (!facility.hasSwimSchedule) {
      parts.add('Hours only');
    }

    parts.add(status.label);
    return parts.join(' · ');
  }
}
