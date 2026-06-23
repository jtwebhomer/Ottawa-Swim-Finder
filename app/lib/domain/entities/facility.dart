import 'facility_type.dart';
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
    this.scheduleMode = FacilityScheduleMode.swimSchedule,
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
  final FacilityScheduleMode scheduleMode;

  bool get isStale => syncStatus == FacilitySyncStatus.stale;

  bool get hasSwimSchedule =>
      scheduleMode == FacilityScheduleMode.swimSchedule;

  bool get isSeasonal =>
      scheduleMode == FacilityScheduleMode.seasonalOnly ||
      facilityType == FacilityType.outdoorPool;

  bool get isIndoorAquatic =>
      facilityType == FacilityType.indoorPool ||
      facilityType == FacilityType.wavePool;

  Facility copyWith({
    bool? isFavorite,
    String? contentHash,
    int? lastUpdated,
    int? lastSuccessfulSyncAt,
    FacilitySyncStatus? syncStatus,
    FacilityType? facilityType,
    FacilityScheduleMode? scheduleMode,
    String? metadataJson,
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
      scheduleMode: scheduleMode ?? this.scheduleMode,
    );
  }
}
