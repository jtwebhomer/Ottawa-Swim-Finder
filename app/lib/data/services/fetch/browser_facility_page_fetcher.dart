import '../../../domain/entities/facility_fetch_tier.dart';

/// Request context for browser-based page loads.
class BrowserFetchRequest {
  const BrowserFetchRequest({
    required this.url,
    this.facilityId,
    this.timeoutMs = 30000,
  });

  final String url;
  final String? facilityId;
  final int timeoutMs;
}

/// JS-enabled fetch used when HTTP Tier 1 returns bot/challenge pages.
abstract class BrowserFacilityPageFetcher {
  bool get isAvailable;

  String get engineLabel;

  Future<FacilityPageFetchResult?> fetch(
    String url, {
    String? facilityId,
    int timeoutMs = 30000,
  });

  Future<FacilityPageFetchResult?> fetchRequest(BrowserFetchRequest request);
}

/// Delegates [fetch] to [fetchRequest] for concrete browser fetchers.
abstract class BrowserFacilityPageFetcherBase implements BrowserFacilityPageFetcher {
  @override
  Future<FacilityPageFetchResult?> fetch(
    String url, {
    String? facilityId,
    int timeoutMs = 30000,
  }) =>
      fetchRequest(
        BrowserFetchRequest(
          url: url,
          facilityId: facilityId,
          timeoutMs: timeoutMs,
        ),
      );
}

/// No-op browser fetcher for tests and unsupported platforms.
class UnavailableBrowserFacilityPageFetcher
    extends BrowserFacilityPageFetcherBase {
  @override
  bool get isAvailable => false;

  @override
  String get engineLabel => 'UNAVAILABLE';

  @override
  Future<FacilityPageFetchResult?> fetchRequest(BrowserFetchRequest request) async =>
      null;
}
