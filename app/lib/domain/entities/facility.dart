import 'facility_type.dart';
import 'schedule_trust_status.dart';
import 'sync_status.dart';

class Facility {
  const Facility({
    required this.id,
    required this.name,
    this.address,
    this.postalCode,
    this.latitude,
    this.longitude,
    this.region,
    this.url,
    this.contentHash,
    this.lastUpdated,
    this.lastSuccessfulSyncAt,
    this.syncStatus = FacilitySyncStatus.ok,
    this.isFavorite = false,
    this.metadataJson,
    this.facilityType = FacilityType.indoorPool,
    this.dataModel = FacilityDataModel.swimSchedule,
    this.displayStatus = FacilityDisplayStatus.liveOk,
    this.scheduleMode = FacilityScheduleMode.swimSchedule,
    this.scheduleTrustStatus = ScheduleTrustStatus.unverified,
    this.scheduleSource = ScheduleSource.none,
    this.scheduleVerifiedAt,
    this.fixtureGeneratedAt,
  });

  final String id;
  final String name;
  final String? address;
  final String? postalCode;
  final double? latitude;
  final double? longitude;
  final String? region;
  final String? url;
  final String? contentHash;
  final int? lastUpdated;
  final int? lastSuccessfulSyncAt;
  final FacilitySyncStatus syncStatus;
  final bool isFavorite;
  final String? metadataJson;
  final FacilityType facilityType;
  final FacilityDataModel dataModel;
  final FacilityDisplayStatus displayStatus;
  final FacilityScheduleMode scheduleMode;
  final ScheduleTrustStatus scheduleTrustStatus;
  final ScheduleSource scheduleSource;
  final int? scheduleVerifiedAt;
  final int? fixtureGeneratedAt;

  bool get isStale => syncStatus == FacilitySyncStatus.stale;

  bool get hasSwimSchedule => dataModel.expectsSwimTable;

  /// True for wading, splash, outdoor seasonal — never use swim empty-state UI.
  bool get hasHoursOnly => !dataModel.expectsSwimTable;

  bool get usesSwimScheduleUi => dataModel.expectsSwimTable;

  bool get isSeasonal =>
      dataModel == FacilityDataModel.mixedSeasonal ||
      dataModel == FacilityDataModel.seasonalHours ||
      displayStatus == FacilityDisplayStatus.seasonal;

  bool get isHoursOnlyFacility =>
      dataModel == FacilityDataModel.hoursOnly ||
      dataModel == FacilityDataModel.statusOnly;

  bool get isIndoorAquatic =>
      facilityType == FacilityType.indoorPool ||
      facilityType == FacilityType.wavePool;

  bool get isOutdoorAquatic =>
      facilityType == FacilityType.outdoorPool ||
      facilityType == FacilityType.wadingPool;

  /// All facility types in this app represent aquatic recreation locations.
  bool get isAquatic => true;

  String get nonSwimScheduleLabel => switch (facilityType) {
        FacilityType.wadingPool => 'Open Hours Only',
        FacilityType.splashPad => 'Seasonal Activity Area',
        FacilityType.outdoorPool => 'Seasonal Schedule',
        _ => scheduleMode.label,
      };

  String get aquaticSettingLabel => switch (facilityType) {
        FacilityType.outdoorPool || FacilityType.wadingPool => 'Outdoor',
        FacilityType.indoorPool || FacilityType.wavePool => 'Indoor',
        FacilityType.splashPad => 'Splash',
      };

  Facility copyWith({
    bool? isFavorite,
    String? contentHash,
    int? lastUpdated,
    int? lastSuccessfulSyncAt,
    FacilitySyncStatus? syncStatus,
    FacilityType? facilityType,
    FacilityDataModel? dataModel,
    FacilityDisplayStatus? displayStatus,
    FacilityScheduleMode? scheduleMode,
    String? metadataJson,
    ScheduleTrustStatus? scheduleTrustStatus,
    ScheduleSource? scheduleSource,
    int? scheduleVerifiedAt,
    int? fixtureGeneratedAt,
  }) {
    return Facility(
      id: id,
      name: name,
      address: address,
      postalCode: postalCode,
      latitude: latitude,
      longitude: longitude,
      region: region,
      url: url,
      contentHash: contentHash ?? this.contentHash,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      lastSuccessfulSyncAt:
          lastSuccessfulSyncAt ?? this.lastSuccessfulSyncAt,
      syncStatus: syncStatus ?? this.syncStatus,
      isFavorite: isFavorite ?? this.isFavorite,
      metadataJson: metadataJson ?? this.metadataJson,
      facilityType: facilityType ?? this.facilityType,
      dataModel: dataModel ?? this.dataModel,
      displayStatus: displayStatus ?? this.displayStatus,
      scheduleMode: scheduleMode ?? this.scheduleMode,
      scheduleTrustStatus: scheduleTrustStatus ?? this.scheduleTrustStatus,
      scheduleSource: scheduleSource ?? this.scheduleSource,
      scheduleVerifiedAt: scheduleVerifiedAt ?? this.scheduleVerifiedAt,
      fixtureGeneratedAt: fixtureGeneratedAt ?? this.fixtureGeneratedAt,
    );
  }
}
