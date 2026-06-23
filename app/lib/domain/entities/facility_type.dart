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

/// Required data model per facility — resolved before scraping.
enum FacilityDataModel {
  swimSchedule('SWIM_SCHEDULE', 'Swim schedule'),
  mixedSeasonal('MIXED_SEASONAL', 'Seasonal schedule'),
  seasonalHours('SEASONAL_HOURS', 'Seasonal hours'),
  hoursOnly('HOURS_ONLY', 'Open hours only'),
  statusOnly('STATUS_ONLY', 'Status only');

  const FacilityDataModel(this.storageKey, this.label);
  final String storageKey;
  final String label;

  static FacilityDataModel? fromStorage(String? value) {
    if (value == null) return null;
    for (final m in FacilityDataModel.values) {
      if (m.storageKey == value || m.name == value) return m;
    }
    return null;
  }

  static FacilityDataModel forType(FacilityType type, {bool? hasSwimSchedule}) {
    if (hasSwimSchedule == false && type == FacilityType.outdoorPool) {
      return FacilityDataModel.mixedSeasonal;
    }
    return switch (type) {
      FacilityType.indoorPool || FacilityType.wavePool => swimSchedule,
      FacilityType.outdoorPool => mixedSeasonal,
      FacilityType.wadingPool || FacilityType.splashPad => hoursOnly,
    };
  }

  bool get expectsSwimTable => this == FacilityDataModel.swimSchedule;

  bool get hasHoursOrSeasonalInfo => !expectsSwimTable;
}

/// API / UI display status — replaces vague "No schedules".
enum FacilityDisplayStatus {
  liveOk('LIVE_OK', 'Live schedules'),
  seasonal('SEASONAL', 'Seasonal hours'),
  hoursOnly('HOURS_ONLY', 'Open hours only'),
  statusOnly('STATUS_ONLY', 'Status only'),
  blocked('BLOCKED', 'Blocked'),
  parseIssue('PARSE_ISSUE', 'Schedule parse issue'),
  stale('STALE', 'Stale — last good data');

  const FacilityDisplayStatus(this.storageKey, this.label);
  final String storageKey;
  final String label;

  static FacilityDisplayStatus? fromStorage(String? value) {
    if (value == null) return null;
    for (final s in FacilityDisplayStatus.values) {
      if (s.storageKey == value || s.name == value) return s;
    }
    return null;
  }

  static FacilityDisplayStatus defaultFor(FacilityDataModel model) {
    return switch (model) {
      FacilityDataModel.mixedSeasonal || FacilityDataModel.seasonalHours => seasonal,
      FacilityDataModel.hoursOnly => hoursOnly,
      FacilityDataModel.statusOnly => statusOnly,
      FacilityDataModel.swimSchedule => liveOk,
    };
  }
}

/// How schedule data is presented for a facility (legacy API compat).
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

  static FacilityScheduleMode forDataModel(FacilityDataModel model) {
    return switch (model) {
      FacilityDataModel.swimSchedule => swimSchedule,
      FacilityDataModel.mixedSeasonal || FacilityDataModel.seasonalHours => seasonalOnly,
      FacilityDataModel.hoursOnly || FacilityDataModel.statusOnly => openHoursOnly,
    };
  }
}

/// UI-facing operational status for browse screen.
enum FacilityBrowseStatus {
  open('Open'),
  seasonal('Seasonal Schedule'),
  hoursOnly('Open Hours Only'),
  statusOnly('Seasonal Activity Area'),
  stale('Stale'),
  parseIssue('Schedule parse issue'),
  closed('Closed');

  const FacilityBrowseStatus(this.label);
  final String label;
}
