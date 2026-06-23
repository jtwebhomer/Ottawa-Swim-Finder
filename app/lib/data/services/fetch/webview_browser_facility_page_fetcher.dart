import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/constants/http_constants.dart';
import '../../../core/logging/app_logger.dart';
import '../../../domain/entities/facility_fetch_tier.dart';
import 'browser_facility_page_fetcher.dart';

/// Headless WebView with JS — Tier 2 on Android/iOS.
class WebViewBrowserFacilityPageFetcher implements BrowserFacilityPageFetcher {
  @override
  bool get isAvailable =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static const _scheduleReadyJs = '''
(function() {
  var tables = document.querySelectorAll('table');
  for (var i = 0; i < tables.length; i++) {
    var cap = tables[i].querySelector('caption');
    var title = (cap ? cap.textContent : '') ||
      (tables[i].previousElementSibling ? tables[i].previousElementSibling.textContent : '');
    if (title.toLowerCase().indexOf('swim') >= 0 ||
        title.toLowerCase().indexOf('aquafit') >= 0) {
      return true;
    }
  }
  return document.body && document.body.innerHTML.length > 8000;
})()
''';

  @override
  Future<FacilityPageFetchResult?> fetch(String url) async {
    if (!isAvailable) return null;

    HeadlessInAppWebView? headless;
    try {
      final completer = Completer<String?>();
      var settled = false;
      String? loadedUrl;

      void finish(String? html) {
        if (settled) return;
        settled = true;
        if (!completer.isCompleted) completer.complete(html);
      }

      headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          domStorageEnabled: true,
          userAgent: HttpConstants.userAgent,
          mediaPlaybackRequiresUserGesture: false,
        ),
        onLoadStop: (controller, currentUrl) async {
          loadedUrl = currentUrl?.toString();
          try {
            for (var i = 0; i < 12; i++) {
              final ready = await controller.evaluateJavascript(
                source: _scheduleReadyJs,
              );
              if (ready == true || ready == 'true') break;
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
        const Duration(seconds: 45),
        onTimeout: () => null,
      );

      if (html == null || html.isEmpty) return null;

      return FacilityPageFetchResult(
        html: html,
        statusCode: 200,
        finalUrl: loadedUrl ?? url,
        contentType: 'text/html',
        tier: FacilityFetchTier.browser,
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
