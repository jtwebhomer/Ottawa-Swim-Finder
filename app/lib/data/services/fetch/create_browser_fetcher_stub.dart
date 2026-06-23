import 'browser_facility_page_fetcher.dart';
import 'playwright_browser_fetcher.dart';

BrowserFacilityPageFetcher createBrowserFacilityPageFetcher() {
  final playwright = PlaywrightBrowserFacilityPageFetcher();
  if (playwright.isAvailable) return playwright;
  return UnavailableBrowserFacilityPageFetcher();
}
