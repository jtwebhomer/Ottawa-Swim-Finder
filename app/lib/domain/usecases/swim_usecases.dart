import '../../core/constants/app_constants.dart';
import '../../core/utils/geo_utils.dart';
import '../../core/utils/ottawa_time.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/repositories/repositories.dart';

class OccupancyEstimator {
  static const weights = {
    SwimCategories.laneSwim: 0.3,
    SwimCategories.generalSwim: 0.8,
    SwimCategories.familySwim: 0.6,
    SwimCategories.aquafit: 0.5,
    SwimCategories.waveSwim: 1.0,
    SwimCategories.adultSwim: 0.5,
    SwimCategories.parentTot: 0.4,
  };

  static String estimate(List<ScheduleEntry> concurrent) {
    var score = 0.0;
    for (final entry in concurrent) {
      score += weights[entry.category] ?? 0.4;
    }
    if (score < 0.5) return 'Low';
    if (score < 1.2) return 'Moderate';
    return 'Busy';
  }
}

class SearchSchedulesUseCase {
  SearchSchedulesUseCase(this._scheduleRepo);

  final ScheduleRepository _scheduleRepo;

  Future<List<ScheduleEntry>> call({
    List<String>? categories,
    String? facilityId,
    String? date,
    String? startAfter,
    String? endBefore,
    double? maxDistanceKm,
    double? userLat,
    double? userLng,
    bool favoritesFirst = true,
  }) {
    return _scheduleRepo.searchSchedules(
      categories: categories,
      facilityId: facilityId,
      date: date,
      startAfter: startAfter,
      endBefore: endBefore,
      maxDistanceKm: maxDistanceKm,
      userLat: userLat,
      userLng: userLng,
      favoritesFirst: favoritesFirst,
    );
  }
}

class GetNearestSwimUseCase {
  GetNearestSwimUseCase(this._scheduleRepo, this._facilityRepo);

  final ScheduleRepository _scheduleRepo;
  final FacilityRepository _facilityRepo;

  Future<ScheduleEntry?> nearestByCategory({
    required String category,
    required double lat,
    required double lng,
    String? date,
  }) async {
    final entries = await _scheduleRepo.searchSchedules(
      categories: [category],
      date: date ?? _today(),
      userLat: lat,
      userLng: lng,
    );
    if (entries.isEmpty) return null;
    return entries.first;
  }

  Future<Map<String, ScheduleEntry?>> nearestHighlights({
    required double lat,
    required double lng,
  }) async {
    final active = await _scheduleRepo.getActiveNow();
    ScheduleEntry? nearestActive;
    var minDist = double.infinity;

    for (final entry in active) {
      final facility = await _facilityRepo.getFacilityById(entry.facilityId);
      if (facility?.latitude == null || facility?.longitude == null) continue;
      final dist = GeoUtils.distanceKm(
        lat,
        lng,
        facility!.latitude!,
        facility.longitude!,
      );
      if (dist < minDist) {
        minDist = dist;
        nearestActive = entry.copyWith(distanceKm: dist, facilityName: facility.name);
      }
    }

    final lane = await nearestByCategory(
      category: SwimCategories.laneSwim,
      lat: lat,
      lng: lng,
    );
    final general = await nearestByCategory(
      category: SwimCategories.generalSwim,
      lat: lat,
      lng: lng,
    );

    return {
      'active': nearestActive,
      'lane': lane,
      'public': general,
    };
  }

  String _today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

class FacilityPinStatusUseCase {
  FacilityPinStatusUseCase(this._scheduleRepo);

  final ScheduleRepository _scheduleRepo;

  Future<Map<String, PinStatus>> getPinStatuses(List<Facility> facilities) async {
    final date = OttawaTime.todayDate();
    final time = OttawaTime.nowTime();

    final result = <String, PinStatus>{};
    for (final facility in facilities) {
      final schedules = await _scheduleRepo.getSchedulesForFacility(facility.id, date: date);
      final swims = schedules
          .where((s) => SwimCategories.all.contains(s.category))
          .toList();

      if (swims.isEmpty) {
        result[facility.id] = PinStatus.inactive;
        continue;
      }

      final hasActive = swims.any(
        (s) => OttawaTime.isActiveAt(start: s.startTime, end: s.endTime, time: time),
      );
      if (hasActive) {
        result[facility.id] = PinStatus.active;
        continue;
      }

      final hasUpcoming = swims.any(
        (s) => OttawaTime.isUpcomingAt(start: s.startTime, time: time),
      );
      result[facility.id] = hasUpcoming ? PinStatus.upcoming : PinStatus.inactive;
    }
    return result;
  }
}

enum PinStatus { active, upcoming, inactive }
