/// Per-facility inclusion audit for discovery diagnostics.
class FacilityInclusionTrace {
  const FacilityInclusionTrace({
    required this.facilityId,
    required this.name,
    required this.facilityType,
    required this.discoveredFromSource,
    required this.storedInDb,
    required this.shownInUi,
    this.sourceRegion,
    this.filterReason,
    this.slugResolution,
    this.parseSuccess,
    this.sessionCount = 0,
    this.notes,
  });

  final String facilityId;
  final String name;
  final String facilityType;
  final bool discoveredFromSource;
  final bool storedInDb;
  final bool shownInUi;
  final String? sourceRegion;
  final String? filterReason;
  final String? slugResolution;
  final bool? parseSuccess;
  final int sessionCount;
  final String? notes;

  bool get included =>
      discoveredFromSource && storedInDb && shownInUi && filterReason == null;

  String summaryLine() {
    final flags = [
      'discovered=${discoveredFromSource ? 'Y' : 'N'}',
      'db=${storedInDb ? 'Y' : 'N'}',
      'ui=${shownInUi ? 'Y' : 'N'}',
      if (filterReason != null) 'filtered=$filterReason',
      if (slugResolution != null) 'slug=$slugResolution',
      if (parseSuccess != null) 'parsed=${parseSuccess! ? 'Y' : 'N'}',
      'sessions=$sessionCount',
    ];
    return '$name ($facilityId): ${flags.join(', ')}';
  }
}

/// Summary of facility catalog audit run.
class FacilityCatalogAudit {
  const FacilityCatalogAudit({
    required this.traces,
    required this.sourceIndoorEnumerated,
    required this.sourceIndoorMarketing,
    required this.discoveredCount,
    required this.canonicalCount,
    required this.dbCount,
    required this.uiCount,
    required this.missingFromDb,
    required this.missingFromSource,
    required this.explanation,
    required this.ranAt,
  });

  final List<FacilityInclusionTrace> traces;
  final int sourceIndoorEnumerated;
  final int sourceIndoorMarketing;
  final int discoveredCount;
  final int canonicalCount;
  final int dbCount;
  final int uiCount;
  final List<String> missingFromDb;
  final List<String> missingFromSource;
  final String explanation;
  final DateTime ranAt;

  int get indoorInDb =>
      traces.where((t) => t.facilityType.startsWith('INDOOR') ||
          t.facilityType == 'WAVE_POOL').length;
}
