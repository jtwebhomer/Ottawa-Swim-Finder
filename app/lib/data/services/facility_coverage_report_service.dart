import '../../core/constants/app_constants.dart';

import '../../core/utils/ottawa_time.dart';

import '../../domain/entities/facility.dart';

import '../../domain/entities/facility_type.dart';

import '../../domain/repositories/repositories.dart';

import 'facility_discovery_service.dart';



class FacilityDiscoveryGap {

  const FacilityDiscoveryGap({

    required this.name,

    required this.reason,

    this.sourceUrl,

  });



  final String name;

  final String reason;

  final String? sourceUrl;

}



class FacilityMapAuditRow {

  const FacilityMapAuditRow({

    required this.name,

    required this.id,

    required this.facilityType,

    required this.inDatabase,

    required this.hasCoordinates,

    required this.visibleOnMap,

    required this.scheduleCount,

    required this.hasSwimSchedule,

  });



  final String name;

  final String id;

  final FacilityType facilityType;

  final bool inDatabase;

  final bool hasCoordinates;

  final bool visibleOnMap;

  final int scheduleCount;

  final bool hasSwimSchedule;

}



class FacilityCoverageReport {

  const FacilityCoverageReport({

    required this.facilitiesByType,

    required this.schedulesByFacility,

    required this.sessionsByCategory,

    required this.unknownCategories,

    required this.facilitiesWithZeroUpcoming,

    required this.staleFacilities,

    required this.discoveredIndoorCount,

    required this.canonicalIndoorCount,

    required this.missingFromDiscovery,

    required this.categoryAudit,

    required this.categoryInventory,

    required this.facilityMapAudit,

    required this.facilitiesMissingSchedules,

    required this.facilitiesHiddenFromMap,

    required this.totalFacilitiesDiscovered,

    required this.outdoorPoolCount,

    required this.wadingPoolCount,

    required this.indoorPoolCount,

    required this.wavePoolCount,

    required this.categoriesDiscovered,

    required this.categoriesVisibleToUsers,

  });



  final Map<String, int> facilitiesByType;

  final Map<String, int> schedulesByFacility;

  final Map<String, int> sessionsByCategory;

  final List<String> unknownCategories;

  final List<String> facilitiesWithZeroUpcoming;

  final List<String> staleFacilities;

  final int discoveredIndoorCount;

  final int canonicalIndoorCount;

  final List<FacilityDiscoveryGap> missingFromDiscovery;

  final List<CategoryAuditRow> categoryAudit;

  final List<CategoryInventoryRow> categoryInventory;

  final List<FacilityMapAuditRow> facilityMapAudit;

  final List<String> facilitiesMissingSchedules;

  final List<String> facilitiesHiddenFromMap;

  final int totalFacilitiesDiscovered;

  final int outdoorPoolCount;

  final int wadingPoolCount;

  final int indoorPoolCount;

  final int wavePoolCount;

  final int categoriesDiscovered;

  final int categoriesVisibleToUsers;

}



/// Diagnostics coverage audit for facilities, schedules, and discovery gaps.

class FacilityCoverageReportService {

  FacilityCoverageReportService({

    required FacilityRepository facilityRepo,

    required ScheduleRepository scheduleRepo,

    required FacilityDiscoveryService discoveryService,

  })  : _facilityRepo = facilityRepo,

        _scheduleRepo = scheduleRepo,

        _discoveryService = discoveryService;



  final FacilityRepository _facilityRepo;

  final ScheduleRepository _scheduleRepo;

  final FacilityDiscoveryService _discoveryService;



  Future<FacilityCoverageReport> build({String? indoorListingHtml}) async {

    final facilities = await _facilityRepo.getAllFacilities();

    final canonical = await _discoveryService.loadCanonicalFacilities();

    final canonicalIds = canonical.map((f) => f.id).toSet();

    final today = OttawaTime.todayDate();



    final byType = <String, int>{};

    for (final type in FacilityType.values) {

      byType[type.label] =

          facilities.where((f) => f.facilityType == type).length;

    }



    final schedulesByFacility = <String, int>{};

    final stale = <String>[];

    final zeroUpcoming = <String>[];

    final missingSchedules = <String>[];

    final hiddenFromMap = <String>[];

    final mapAudit = <FacilityMapAuditRow>[];



    for (final facility in facilities) {

      final count = await _scheduleRepo.countSchedulesForFacility(facility.id);

      schedulesByFacility[facility.name] = count;



      if (facility.isStale) stale.add(facility.name);



      if (facility.hasSwimSchedule && count == 0) {

        missingSchedules.add(facility.name);

      }



      final hasCoords = facility.latitude != null && facility.longitude != null;

      final visibleOnMap = hasCoords && facility.isAquatic;

      if (!visibleOnMap && facility.isAquatic) {

        hiddenFromMap.add(facility.name);

      }



      mapAudit.add(

        FacilityMapAuditRow(

          name: facility.name,

          id: facility.id,

          facilityType: facility.facilityType,

          inDatabase: true,

          hasCoordinates: hasCoords,

          visibleOnMap: visibleOnMap,

          scheduleCount: count,

          hasSwimSchedule: facility.hasSwimSchedule,

        ),

      );

    }



    for (final c in canonical) {

      if (facilities.any((f) => f.id == c.id)) continue;

      mapAudit.add(

        FacilityMapAuditRow(

          name: c.name,

          id: c.id,

          facilityType: c.facilityType,

          inDatabase: false,

          hasCoordinates: c.latitude != null && c.longitude != null,

          visibleOnMap: false,

          scheduleCount: 0,

          hasSwimSchedule: c.hasSwimSchedule,

        ),

      );

    }



    for (final facility in facilities) {

      if (!facility.hasSwimSchedule) continue;

      final upcoming = await _scheduleRepo.getUpcomingSwims(

        facilityId: facility.id,

        fromDate: today,

        limit: 1,

      );

      if (upcoming.isEmpty) zeroUpcoming.add(facility.name);

    }



    final categoryAudit = await _scheduleRepo.getCategoryAuditReport();

    final categoryInventory = await _scheduleRepo.getCategoryInventory();

    final sessionsByCategory = <String, int>{};

    for (final row in categoryAudit) {

      final key = row.rawCategory;

      sessionsByCategory[key] = (sessionsByCategory[key] ?? 0) + row.occurrences;

    }



    final unknown = await _scheduleRepo.getUnknownRawCategories();



    final canonicalIndoor = facilities

        .where((f) =>

            f.facilityType == FacilityType.indoorPool ||

            f.facilityType == FacilityType.wavePool)

        .length;



    final discovered = indoorListingHtml != null

        ? _discoveryService.parseIndoorListingForTest(indoorListingHtml)

        : await _discoveryService.discoverIndoorPoolsFromSource();



    final discoveredSlugs = discovered.map((d) => d.slug).toSet();

    final canonicalSwimFacilities = facilities.where(

      (f) => f.hasSwimSchedule && f.facilityType != FacilityType.outdoorPool,

    );



    final missing = <FacilityDiscoveryGap>[];

    for (final facility in canonicalSwimFacilities) {

      if (!discoveredSlugs.contains(facility.id)) {

        missing.add(

          FacilityDiscoveryGap(

            name: facility.name,

            reason: 'Not returned by live indoor listing parse',

            sourceUrl: AppConstants.indoorPoolsUrl,

          ),

        );

      }

    }



    final rawDiscovered = categoryInventory.map((r) => r.rawCategory).toSet();



    return FacilityCoverageReport(

      facilitiesByType: byType,

      schedulesByFacility: schedulesByFacility,

      sessionsByCategory: sessionsByCategory,

      unknownCategories: unknown,

      facilitiesWithZeroUpcoming: zeroUpcoming,

      staleFacilities: stale,

      discoveredIndoorCount: discovered.length,

      canonicalIndoorCount: canonicalIndoor,

      missingFromDiscovery: missing,

      categoryAudit: categoryAudit,

      categoryInventory: categoryInventory,

      facilityMapAudit: mapAudit,

      facilitiesMissingSchedules: missingSchedules,

      facilitiesHiddenFromMap: hiddenFromMap,

      totalFacilitiesDiscovered: facilities.length,

      outdoorPoolCount:

          facilities.where((f) => f.facilityType == FacilityType.outdoorPool).length,

      wadingPoolCount:

          facilities.where((f) => f.facilityType == FacilityType.wadingPool).length,

      indoorPoolCount:

          facilities.where((f) => f.facilityType == FacilityType.indoorPool).length,

      wavePoolCount:

          facilities.where((f) => f.facilityType == FacilityType.wavePool).length,

      categoriesDiscovered: rawDiscovered.length,

      categoriesVisibleToUsers: rawDiscovered.length,

    );

  }

}

