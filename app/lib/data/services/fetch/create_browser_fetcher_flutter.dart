import 'dart:io';

import 'browser_facility_page_fetcher.dart';
import 'playwright_browser_fetcher.dart';
import 'playwright_sync_service.dart';
import 'webview_browser_facility_page_fetcher.dart';

BrowserFacilityPageFetcher createBrowserFacilityPageFetcher({
  PlaywrightSyncService? syncService,
}) {
  if (Platform.isAndroid || Platform.isIOS) {
    return WebViewBrowserFacilityPageFetcher();
  }
  final playwright = PlaywrightBrowserFacilityPageFetcher(
    syncService: syncService,
  );
  if (playwright.isAvailable) return playwright;
  return UnavailableBrowserFacilityPageFetcher();
}
