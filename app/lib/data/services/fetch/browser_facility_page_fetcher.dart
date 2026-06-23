import '../../../domain/entities/facility_fetch_tier.dart';

/// JS-enabled fetch used when HTTP Tier 1 returns bot/challenge pages.
abstract class BrowserFacilityPageFetcher {
  bool get isAvailable;

  Future<FacilityPageFetchResult?> fetch(String url);
}

/// No-op browser fetcher for tests and unsupported platforms.
class UnavailableBrowserFacilityPageFetcher
    implements BrowserFacilityPageFetcher {
  @override
  bool get isAvailable => false;

  @override
  Future<FacilityPageFetchResult?> fetch(String url) async => null;
}
