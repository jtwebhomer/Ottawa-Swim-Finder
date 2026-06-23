import 'dart:convert';

import '../../domain/entities/facility.dart';
import '../../domain/entities/facility_type.dart';

/// Data-model-driven availability copy — never infer emptiness from swim sessions.
class FacilityAvailabilityPresenter {
  static bool usesSwimScheduleUi(Facility facility) =>
      facility.dataModel.expectsSwimTable;

  static String headline(Facility facility) => switch (facility.dataModel) {
        FacilityDataModel.swimSchedule => 'Swim schedule',
        FacilityDataModel.mixedSeasonal ||
        FacilityDataModel.seasonalHours =>
          'Seasonal Schedule',
        FacilityDataModel.hoursOnly => 'Open Hours Only',
        FacilityDataModel.statusOnly => 'Seasonal Activity Area',
      };

  static String detail(Facility facility) {
    final meta = _parseMetadata(facility.metadataJson);
    final hours = meta['hoursText'] as String?;
    final seasonStart = meta['seasonStart'] as String?;
    final seasonEnd = meta['seasonEnd'] as String?;
    final season = meta['season'] as String?;

    return switch (facility.dataModel) {
      FacilityDataModel.swimSchedule => '',
      FacilityDataModel.mixedSeasonal ||
      FacilityDataModel.seasonalHours =>
        _seasonalDetail(hours: hours, seasonStart: seasonStart, seasonEnd: seasonEnd, season: season),
      FacilityDataModel.hoursOnly =>
        _hoursDetail(hours: hours, season: season, facility: facility),
      FacilityDataModel.statusOnly =>
        _statusDetail(facility: facility),
    };
  }

  static String mapSheetMessage(Facility facility) {
    if (usesSwimScheduleUi(facility)) {
      return 'No swims scheduled today. Check Tonight or Tomorrow for upcoming sessions.';
    }
    final body = detail(facility);
    if (body.isNotEmpty) return body;
    return '${headline(facility)} — visit ottawa.ca for current hours and status.';
  }

  static String _seasonalDetail({
    String? hours,
    String? seasonStart,
    String? seasonEnd,
    String? season,
  }) {
    final parts = <String>['Seasonal outdoor pool.'];
    if (seasonStart != null && seasonEnd != null) {
      parts.add('Season: $seasonStart – $seasonEnd.');
    } else if (season != null && season.isNotEmpty) {
      parts.add('Season: $season.');
    }
    if (hours != null && hours.isNotEmpty) {
      parts.add(hours);
    } else {
      parts.add('Check ottawa.ca for opening dates and daily hours.');
    }
    return parts.join(' ');
  }

  static String _hoursDetail({
    String? hours,
    String? season,
    required Facility facility,
  }) {
    final parts = <String>[];
    if (facility.facilityType == FacilityType.splashPad) {
      parts.add('Seasonal splash pad.');
    } else if (facility.facilityType == FacilityType.wadingPool) {
      parts.add('Seasonal wading pool.');
    } else {
      parts.add('Open-hours facility.');
    }
    if (season != null && season.isNotEmpty) {
      parts.add('Season: $season.');
    }
    if (hours != null && hours.isNotEmpty) {
      parts.add(hours);
    } else {
      parts.add('Operating hours are published on ottawa.ca.');
    }
    return parts.join(' ');
  }

  static String _statusDetail({required Facility facility}) {
    if (facility.facilityType == FacilityType.splashPad) {
      return 'Seasonal activity area. Check ottawa.ca for open/closed status.';
    }
    return 'Availability status only — see ottawa.ca for current information.';
  }

  static Map<String, dynamic> _parseMetadata(String? json) {
    if (json == null || json.isEmpty) return {};
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return {};
  }
}
