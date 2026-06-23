import 'dart:io';

import 'browser_facility_page_fetcher.dart';
import 'playwright_browser_fetcher.dart';
import 'webview_browser_facility_page_fetcher.dart';

BrowserFacilityPageFetcher createBrowserFacilityPageFetcher() {
  if (Platform.isAndroid || Platform.isIOS) {
    return WebViewBrowserFacilityPageFetcher();
  }
  final playwright = PlaywrightBrowserFacilityPageFetcher();
  if (playwright.isAvailable) return playwright;
  return UnavailableBrowserFacilityPageFetcher();
}
