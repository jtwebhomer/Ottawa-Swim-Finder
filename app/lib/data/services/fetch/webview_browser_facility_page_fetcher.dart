import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/constants/http_constants.dart';
import '../../../core/logging/app_logger.dart';
import '../../../domain/entities/facility_fetch_tier.dart';
import 'browser_facility_page_fetcher.dart';

/// Headless WebView with JS — primary browser engine on Android/iOS.
class WebViewBrowserFacilityPageFetcher extends BrowserFacilityPageFetcherBase {
  @override
  bool get isAvailable =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  String get engineLabel => 'WEBVIEW';

  static const _expandAndReadyJs = '''
(function() {
  var expanded = 0;
  var clickIfVisible = function(el) {
    if (!el || el.offsetParent === null) return false;
    try { el.click(); return true; } catch(e) { return false; }
  };
  var selectors = [
    'details:not([open]) > summary',
    '[aria-expanded="false"]',
    '.accordion-button.collapsed',
    '[data-toggle="collapse"]'
  ];
  for (var s = 0; s < selectors.length; s++) {
    var nodes = document.querySelectorAll(selectors[s]);
    for (var i = 0; i < nodes.length; i++) {
      if (clickIfVisible(nodes[i])) expanded++;
    }
  }
  var tables = document.querySelectorAll('table');
  var swimTables = 0;
  for (var t = 0; t < tables.length; t++) {
    var cap = tables[t].querySelector('caption');
    var title = (cap ? cap.textContent : '') ||
      (tables[t].previousElementSibling ? tables[t].previousElementSibling.textContent : '');
    if (title.toLowerCase().indexOf('swim') >= 0 ||
        title.toLowerCase().indexOf('aquafit') >= 0) {
      swimTables++;
    }
  }
  return {
    expanded: expanded,
    swimTables: swimTables,
    domSize: document.body ? document.body.innerHTML.length : 0,
    ready: swimTables > 0 || (document.body && document.body.innerHTML.length > 8000)
  };
})()
''';

  @override
  Future<FacilityPageFetchResult?> fetchRequest(BrowserFetchRequest request) async {
    if (!isAvailable) return null;

    final started = DateTime.now();
    HeadlessInAppWebView? headless;
    try {
      final completer = Completer<String?>();
      var settled = false;
      String? loadedUrl;
      int? domSize;
      int? scheduleTableCount;

      void finish(String? html) {
        if (settled) return;
        settled = true;
        if (!completer.isCompleted) completer.complete(html);
      }

      headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(request.url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          userAgent: HttpConstants.userAgent,
          mediaPlaybackRequiresUserGesture: false,
        ),
        onLoadStop: (controller, currentUrl) async {
          loadedUrl = currentUrl?.toString();
          try {
            await Future<void>.delayed(const Duration(milliseconds: 800));
            for (var i = 0; i < 24; i++) {
              final raw = await controller.evaluateJavascript(
                source: _expandAndReadyJs,
              );
              if (raw is Map) {
                domSize = raw['domSize'] as int?;
                scheduleTableCount = raw['swimTables'] as int?;
                if (raw['ready'] == true) break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 500));
            }
            final html = await controller.getHtml();
            finish(html);
          } catch (e) {
            finish(null);
          }
        },
        onReceivedError: (controller, request, error) {
          finish(null);
        },
      );

      await headless.run();
      final html = await completer.future.timeout(
        Duration(milliseconds: request.timeoutMs + 15000),
        onTimeout: () => null,
      );

      if (html == null || html.isEmpty) return null;

      return FacilityPageFetchResult(
        html: html,
        statusCode: 200,
        finalUrl: loadedUrl ?? request.url,
        contentType: 'text/html',
        tier: FacilityFetchTier.browser,
        domSizeBytes: domSize ?? html.length,
        loadTimeMs: DateTime.now().difference(started).inMilliseconds,
        scheduleTableCount: scheduleTableCount,
        syncEngineLabel: engineLabel,
      );
    } catch (e, st) {
      appLogger.w('WebView browser fetch failed', error: e, stackTrace: st);
      return null;
    } finally {
      try {
        await headless?.dispose();
      } catch (_) {}
    }
  }
}
