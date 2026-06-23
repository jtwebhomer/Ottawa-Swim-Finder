import 'browser_facility_page_fetcher.dart';
import 'playwright_browser_fetcher.dart';
import 'playwright_sync_service.dart';

BrowserFacilityPageFetcher createBrowserFacilityPageFetcher({
  PlaywrightSyncService? syncService,
}) {
  final playwright = PlaywrightBrowserFacilityPageFetcher(
    syncService: syncService,
  );
  if (playwright.isAvailable) return playwright;
  return UnavailableBrowserFacilityPageFetcher();
}
