import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/entities/facility.dart';
import '../../domain/entities/facility_inclusion_trace.dart';
import '../../domain/entities/facility_type.dart';
import '../../domain/repositories/repositories.dart';
import 'facility_discovery_service.dart';

/// Compares Ottawa source, discovery, DB, and UI facility lists.
class FacilityInclusionAuditService {
  FacilityInclusionAuditService({
    required FacilityRepository facilityRepo,
    required ScheduleRepository scheduleRepo,
    required FacilityDiscoveryService discoveryService,
  })  : _facilityRepo = facilityRepo,
        _scheduleRepo = scheduleRepo,
        _discovery = discoveryService;

  final FacilityRepository _facilityRepo;
  final ScheduleRepository _scheduleRepo;
  final FacilityDiscoveryService _discovery;

  Future<FacilityCatalogAudit> runAudit({List<Facility>? uiFacilities}) async {
    final meta = await _loadMeta();
    final canonical = await _discovery.loadCanonicalFacilities();
    final discovered = await _discovery.discoverIndoorPoolsFromSource();
    final dbFacilities = await _facilityRepo.getAllFacilities();
    final uiList = uiFacilities ?? dbFacilities;

    final canonicalById = {for (final f in canonical) f.id: f};
    final dbById = {for (final f in dbFacilities) f.id: f};
    final discoveredBySlug = {for (final d in discovered) d.slug: d};

    final indoorCanonical = canonical
        .where((f) =>
            f.facilityType == FacilityType.indoorPool ||
            f.facilityType == FacilityType.wavePool)
        .toList();

    final traces = <FacilityInclusionTrace>[];

    for (final row in discovered) {
      final canonicalRow = canonicalById[row.slug];
      final dbRow = dbById[row.slug];
      final sessions = dbRow != null
          ? await _scheduleRepo.countSchedulesForFacility(row.slug)
          : 0;

      traces.add(
        FacilityInclusionTrace(
          facilityId: row.slug,
          name: row.name,
          facilityType: (canonicalRow?.facilityType ?? FacilityType.indoorPool)
              .storageKey,
          discoveredFromSource: true,
          storedInDb: dbRow != null,
          shownInUi: uiList.any((f) => f.id == row.slug),
          sourceRegion: row.region,
          slugResolution: row.slugResolution,
          parseSuccess: sessions > 0 ? true : null,
          sessionCount: sessions,
        ),
      );
    }

    for (final f in canonical) {
      if (discoveredBySlug.containsKey(f.id)) continue;
      final dbRow = dbById[f.id];
      final sessions = dbRow != null
          ? await _scheduleRepo.countSchedulesForFacility(f.id)
          : 0;

      traces.add(
        FacilityInclusionTrace(
          facilityId: f.id,
          name: f.name,
          facilityType: f.facilityType.storageKey,
          discoveredFromSource: false,
          storedInDb: dbRow != null,
          shownInUi: uiList.any((u) => u.id == f.id),
          filterReason: f.facilityType == FacilityType.indoorPool ||
                  f.facilityType == FacilityType.wavePool
              ? 'not_on_indoor_drop_in_page'
              : 'canonical_supplement',
          slugResolution: 'canonical_only',
          parseSuccess: sessions > 0 ? true : null,
          sessionCount: sessions,
          notes: f.facilityType == FacilityType.wadingPool
              ? 'Seasonal wading — open hours only'
              : f.facilityType == FacilityType.outdoorPool
                  ? 'Seasonal outdoor pool'
                  : null,
        ),
      );
    }

    final enumerated = meta['enumerated_indoor_count'] as int? ?? 20;
    final marketing = meta['city_marketing_indoor_count'] as int? ?? 21;

    final missingFromDb = discovered
        .where((d) => !dbById.containsKey(d.slug))
        .map((d) => d.slug)
        .toList();

    final missingFromSource = indoorCanonical
        .where((c) => !discoveredBySlug.containsKey(c.id))
        .map((c) => c.id)
        .toList();

    final explanation = _buildExplanation(
      enumerated: enumerated,
      marketing: marketing,
      discovered: discovered.length,
      dbIndoor: dbFacilities
          .where((f) =>
              f.facilityType == FacilityType.indoorPool ||
              f.facilityType == FacilityType.wavePool)
          .length,
      missingFromDb: missingFromDb,
      missingFromSource: missingFromSource,
    );

    traces.sort((a, b) => a.name.compareTo(b.name));

    return FacilityCatalogAudit(
      traces: traces,
      sourceIndoorEnumerated: enumerated,
      sourceIndoorMarketing: marketing,
      discoveredCount: discovered.length,
      canonicalCount: canonical.length,
      dbCount: dbFacilities.length,
      uiCount: uiList.length,
      missingFromDb: missingFromDb,
      missingFromSource: missingFromSource,
      explanation: explanation,
      ranAt: DateTime.now(),
    );
  }

  String _buildExplanation({
    required int enumerated,
    required int marketing,
    required int discovered,
    required int dbIndoor,
    required List<String> missingFromDb,
    required List<String> missingFromSource,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Ottawa marketing cites $marketing indoor pools; the official drop-in '
      'listing enumerates $enumerated facilities.',
    );
    buffer.writeln(
      'Live discovery parsed $discovered indoor rows from the source page.',
    );
    buffer.writeln('Database has $dbIndoor indoor/wave facilities.');

    if (missingFromDb.isEmpty && discovered >= enumerated) {
      buffer.writeln(
        'No indoor facility from the source list is missing from the database.',
      );
    } else if (missingFromDb.isNotEmpty) {
      buffer.writeln(
        'Missing from DB: ${missingFromDb.join(', ')}',
      );
    }

    if (missingFromSource.isNotEmpty) {
      buffer.writeln(
        'Canonical entries not on indoor drop-in page: '
        '${missingFromSource.join(', ')} (outdoor/wading/supplement).',
      );
    }

    if (marketing > enumerated && discovered == enumerated) {
      buffer.writeln(
        'COUNT_MISMATCH: The "missing" 21st indoor pool is not named on '
        'ottawa.ca\'s drop-in listing — likely a city headline count vs '
        'enumerated list discrepancy, not an app filter bug.',
      );
    }

    return buffer.toString().trim();
  }

  Future<Map<String, dynamic>> _loadMeta() async {
    final jsonStr =
        await rootBundle.loadString('assets/facilities_canonical.json');
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    return (data['meta'] as Map<String, dynamic>?) ?? {};
  }
}
