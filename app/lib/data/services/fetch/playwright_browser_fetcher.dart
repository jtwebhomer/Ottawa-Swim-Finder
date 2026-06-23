import 'dart:convert';
import 'dart:io';

import '../../../core/logging/app_logger.dart';
import '../../../domain/entities/facility_fetch_tier.dart';
import 'browser_facility_page_fetcher.dart';

/// Playwright-backed Tier 2 for dev machines, CI, and `dart run tool/*` scripts.
class PlaywrightBrowserFacilityPageFetcher implements BrowserFacilityPageFetcher {
  PlaywrightBrowserFacilityPageFetcher({
    this.scriptPath = 'tool/playwright_fetch.mjs',
  });

  final String scriptPath;
  bool? _cachedAvailable;

  @override
  bool get isAvailable {
    if (Platform.isAndroid || Platform.isIOS) return false;
    _cachedAvailable ??= _probeNodeAndScript();
    return _cachedAvailable!;
  }

  bool _probeNodeAndScript() {
    try {
      if (File(scriptPath).existsSync()) return true;
      final fromApp = File('app/$scriptPath');
      return fromApp.existsSync();
    } catch (_) {
      return false;
    }
  }

  String _resolveScriptPath() {
    if (File(scriptPath).existsSync()) return scriptPath;
    final fromApp = 'app/$scriptPath';
    if (File(fromApp).existsSync()) return fromApp;
    return scriptPath;
  }

  @override
  Future<FacilityPageFetchResult?> fetch(String url) async {
    if (!isAvailable) return null;

    final script = _resolveScriptPath();
    try {
      final result = await Process.run(
        'node',
        [script, url],
        runInShell: true,
      );
      if (result.exitCode != 0) {
        appLogger.w(
          'Playwright fetch failed (${result.exitCode}): ${result.stderr}',
        );
        return null;
      }

      final stdout = (result.stdout as String).trim();
      final jsonLine = stdout.split('\n').lastWhere(
            (line) => line.trim().startsWith('{'),
            orElse: () => stdout,
          );
      final data = json.decode(jsonLine) as Map<String, dynamic>;
      final html = data['html'] as String?;
      if (html == null || html.isEmpty) return null;

      return FacilityPageFetchResult(
        html: html,
        statusCode: (data['status'] as num?)?.toInt() ?? 200,
        finalUrl: data['finalUrl'] as String? ?? url,
        contentType: 'text/html',
        tier: FacilityFetchTier.browser,
      );
    } catch (e, st) {
      appLogger.w('Playwright browser fetch error', error: e, stackTrace: st);
      return null;
    }
  }
}
