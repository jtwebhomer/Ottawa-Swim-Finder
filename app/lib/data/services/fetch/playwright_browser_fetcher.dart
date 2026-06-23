import 'dart:convert';
import 'dart:io';

import '../../../core/logging/app_logger.dart';
import '../../../domain/entities/facility_fetch_tier.dart';
import 'browser_facility_page_fetcher.dart';
import 'playwright_sync_service.dart';

/// Playwright-backed browser fetch — uses session server when active.
class PlaywrightBrowserFacilityPageFetcher extends BrowserFacilityPageFetcherBase {
  PlaywrightBrowserFacilityPageFetcher({
    this.scriptPath = 'tool/playwright_fetch.mjs',
    PlaywrightSyncService? syncService,
  }) : _syncService = syncService ?? PlaywrightSyncService();

  final String scriptPath;
  final PlaywrightSyncService _syncService;
  bool? _cachedAvailable;

  PlaywrightSyncService get syncService => _syncService;

  @override
  bool get isAvailable {
    if (Platform.isAndroid || Platform.isIOS) return false;
    _cachedAvailable ??= _syncService.isAvailable;
    return _cachedAvailable!;
  }

  @override
  String get engineLabel => 'PLAYWRIGHT';

  @override
  Future<FacilityPageFetchResult?> fetchRequest(BrowserFetchRequest request) async {
    if (!isAvailable) return null;

    final pageResult = await _syncService.loadFacilityPage(
      url: request.url,
      facilityId: request.facilityId ?? 'unknown',
      timeoutMs: request.timeoutMs,
    );

    if (pageResult.isOk) {
      return _syncService.toFetchResult(pageResult);
    }

    if (pageResult.html != null && pageResult.html!.isNotEmpty) {
      return FacilityPageFetchResult(
        html: pageResult.html!,
        statusCode: pageResult.httpStatus > 0 ? pageResult.httpStatus : 403,
        finalUrl: pageResult.finalUrl ?? request.url,
        contentType: 'text/html',
        tier: FacilityFetchTier.browser,
        domSizeBytes: pageResult.domSize,
        loadTimeMs: pageResult.loadTimeMs,
        scheduleTableCount: pageResult.scheduleTableCount,
        syncEngineLabel: engineLabel,
      );
    }

  // One-shot fallback if session not used and subprocess path needed
    return _oneShotFetch(request.url);
  }

  Future<FacilityPageFetchResult?> _oneShotFetch(String url) async {
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
        domSizeBytes: (data['domSize'] as num?)?.toInt(),
        loadTimeMs: (data['loadTimeMs'] as num?)?.toInt(),
        scheduleTableCount: (data['scheduleTableCount'] as num?)?.toInt(),
        syncEngineLabel: engineLabel,
      );
    } catch (e, st) {
      appLogger.w('Playwright browser fetch error', error: e, stackTrace: st);
      return null;
    }
  }

  String _resolveScriptPath() {
    if (File(scriptPath).existsSync()) return scriptPath;
    final fromApp = 'app/$scriptPath';
    if (File(fromApp).existsSync()) return fromApp;
    return scriptPath;
  }
}
