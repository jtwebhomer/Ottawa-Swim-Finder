/// Per-facility schedule data trust level shown in UI and diagnostics.
enum ScheduleTrustStatus {
  verified('VERIFIED', 'Verified'),
  fixture('FIXTURE', 'Bundled schedule'),
  cached('CACHED', 'Cached schedule'),
  stale('STALE', 'May be outdated'),
  unverified('UNVERIFIED', 'Not yet verified');

  const ScheduleTrustStatus(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static ScheduleTrustStatus? fromStorage(String? value) {
    if (value == null) return null;
    for (final s in ScheduleTrustStatus.values) {
      if (s.storageKey == value || s.name == value.toLowerCase()) return s;
    }
    return null;
  }
}

/// Origin of schedule rows stored for a facility.
enum ScheduleSource {
  live('live'),
  fixture('fixture'),
  backendVerified('backend_verified'),
  none('none');

  const ScheduleSource(this.storageKey);
  final String storageKey;

  static ScheduleSource? fromStorage(String? value) {
    if (value == null) return null;
    for (final s in ScheduleSource.values) {
      if (s.storageKey == value) return s;
    }
    return null;
  }
}
