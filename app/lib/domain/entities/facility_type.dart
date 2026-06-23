/// City of Ottawa aquatic facility classification.
enum FacilityType {
  indoorPool('INDOOR_POOL', 'Indoor Pool'),
  outdoorPool('OUTDOOR_POOL', 'Outdoor Pool'),
  wadingPool('WADING_POOL', 'Wading Pool'),
  wavePool('WAVE_POOL', 'Wave Pool'),
  splashPad('SPLASH_PAD', 'Splash Pad');

  const FacilityType(this.storageKey, this.label);
  final String storageKey;
  final String label;

  static FacilityType? fromStorage(String? value) {
    if (value == null) return null;
    for (final t in FacilityType.values) {
      if (t.storageKey == value || t.name == value) return t;
    }
    return null;
  }

  static FacilityType inferFromIdAndName({
    required String id,
    required String name,
    String? explicit,
  }) {
    final fromExplicit = fromStorage(explicit);
    if (fromExplicit != null) return fromExplicit;

    final lower = '${id.toLowerCase()} ${name.toLowerCase()}';
    if (lower.contains('splash') && lower.contains('pad')) {
      return FacilityType.splashPad;
    }
    if (lower.contains('wading')) return FacilityType.wadingPool;
    if (lower.contains('wave pool') || id == 'splash-wave-pool') {
      return FacilityType.wavePool;
    }
    if (lower.contains('outdoor') ||
        _outdoorPoolIds.contains(id) ||
        _outdoorNameFragments.any(lower.contains)) {
      return FacilityType.outdoorPool;
    }
    return FacilityType.indoorPool;
  }

  static const _outdoorPoolIds = {
    'bearbrook-pool',
    'beaverbrook-pool-kanata',
    'corkstown-pool',
    'crestview-pool',
    'entrance-pool',
    'general-burns-pool',
    'genest-pool',
    'glen-cairn-pool',
    'katimavik-pool',
  };

  static const _outdoorNameFragments = [
    'bearbrook',
    'beaverbrook',
    'corkstown',
    'crestview',
    'entrance pool',
    'general burns',
    'genest pool',
    'glen cairn',
    'katimavik',
  ];
}

/// How schedule data is presented for a facility.
enum FacilityScheduleMode {
  swimSchedule('HAS_SWIM_SCHEDULE', 'Has Swim Schedule'),
  openHoursOnly('OPEN_HOURS_ONLY', 'Open Hours Only'),
  seasonalOnly('SEASONAL_ONLY', 'Seasonal Only');

  const FacilityScheduleMode(this.storageKey, this.label);
  final String storageKey;
  final String label;

  static FacilityScheduleMode? fromStorage(String? value) {
    if (value == null) return null;
    for (final m in FacilityScheduleMode.values) {
      if (m.storageKey == value || m.name == value) return m;
    }
    return null;
  }

  static FacilityScheduleMode forType(FacilityType type) {
    return switch (type) {
      FacilityType.indoorPool || FacilityType.wavePool => swimSchedule,
      FacilityType.outdoorPool => seasonalOnly,
      FacilityType.wadingPool || FacilityType.splashPad => openHoursOnly,
    };
  }
}

/// UI-facing operational status for browse screen.
enum FacilityBrowseStatus {
  open('Open'),
  seasonal('Seasonal'),
  stale('Stale'),
  noSchedule('No schedule'),
  closed('Closed');

  const FacilityBrowseStatus(this.label);
  final String label;
}
