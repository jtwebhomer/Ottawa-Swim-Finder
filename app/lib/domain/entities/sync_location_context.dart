/// Ottawa anchor when GPS is unavailable.
class SyncLocationContext {
  const SyncLocationContext({
    required this.latitude,
    required this.longitude,
    required this.usesDeviceLocation,
  });

  /// Parliament Hill, Ottawa.
  static const fallbackLatitude = 45.4236;
  static const fallbackLongitude = -75.7009;

  const factory SyncLocationContext.fallback() = _FallbackLocation;

  factory SyncLocationContext.fromDevice({
    required double latitude,
    required double longitude,
  }) =>
      SyncLocationContext(
        latitude: latitude,
        longitude: longitude,
        usesDeviceLocation: true,
      );

  final double latitude;
  final double longitude;
  final bool usesDeviceLocation;
}

class _FallbackLocation extends SyncLocationContext {
  const _FallbackLocation()
      : super(
          latitude: SyncLocationContext.fallbackLatitude,
          longitude: SyncLocationContext.fallbackLongitude,
          usesDeviceLocation: false,
        );
}
