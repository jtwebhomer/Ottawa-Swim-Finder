/// Swim category constants and display labels.
///
/// Categories are normalized types — see [SwimTypeNormalizer] for raw-name mapping.
class SwimCategories {
  static const generalSwim = 'general_swim';
  static const laneSwim = 'lane_swim';
  static const familySwim = 'family_swim';
  static const parentTot = 'parent_tot';
  static const aquafit = 'aquafit';
  static const adultSwim = 'adult_swim';
  static const womensSwim = 'womens_swim';
  static const therapeuticSwim = 'therapeutic_swim';
  static const waveSwim = 'wave_swim';
  static const preschoolSwim = 'preschool_swim';

  /// Legacy aliases (mapped on read/write).
  static const publicSwim = generalSwim;
  static const openSwim = generalSwim;

  static const all = [
    generalSwim,
    laneSwim,
    familySwim,
    parentTot,
    aquafit,
    adultSwim,
    womensSwim,
    therapeuticSwim,
    waveSwim,
    preschoolSwim,
  ];

  static const filterLabels = {
    generalSwim: 'General Swim',
    laneSwim: 'Lane Swim',
    familySwim: 'Family Swim',
    parentTot: 'Parent & Tot',
    aquafit: 'Aquafit',
    adultSwim: 'Adult Swim',
    womensSwim: "Women's Swim",
    therapeuticSwim: 'Therapeutic',
    waveSwim: 'Wave Swim',
    preschoolSwim: 'Preschool',
  };

  static String labelFor(String category) =>
      filterLabels[normalizeStored(category)] ??
      category.replaceAll('_', ' ');

  static String displayName({
    required String category,
    String? rawName,
  }) {
    final raw = rawName?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return labelFor(category);
  }

  static String normalizeStored(String category) {
    switch (category) {
      case 'public_swim':
      case 'open_swim':
      case 'other':
        return generalSwim;
      default:
        return all.contains(category) ? category : generalSwim;
    }
  }
}

class AppConstants {
  static const syncIntervalDays = 7;
  static const syncIntervalHours = syncIntervalDays * 24;

  static const settingsLastSyncedAppVersion = 'last_synced_app_version';
  static const settingsStaleThresholdHours = 'sync_stale_threshold_hours';
  static const settingsSyncRotationIndex = 'sync_rotation_index';
  static const settingsLastCatalogSyncAt = 'last_catalog_sync_at';
  static const settingsWelcomeComplete = 'onboarding_complete';
  static const syncTaskName = 'ottawaSwimSync';
  static const userAgent = 'OttawaSwimFinder/1.0';
  static const ottawaBaseUrl = 'https://ottawa.ca';
  static const indoorPoolsUrl =
      '$ottawaBaseUrl/en/drop-swimming-and-aquafitness/indoor-pools-drop-locations';

  static const osmTileUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const osmUserAgentPackage = 'ca.ottawa.ottawa_swim_finder';
}
