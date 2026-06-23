import 'package:http/http.dart' as http;

import '../../../core/logging/app_logger.dart';
import '../../../domain/entities/facility_fetch_tier.dart';
import '../../../domain/entities/sync_engine_mode.dart';
import '../blocked_page_detector.dart';
import '../ottawa_http_client.dart';
import '../scrape_http_exception.dart';
import 'browser_facility_page_fetcher.dart';
import 'create_browser_fetcher.dart';
import 'html_snapshot_cache.dart';

/// Result of the 3-tier resilient fetch pipeline.
class TieredFetchResult {
  const TieredFetchResult({
    required this.outcome,
    required this.attempts,
    this.page,
    this.errorMessage,
    this.httpStatus,
    this.usedHttpFallback = false,
  });

  final FacilityPageFetchResult? page;
  final TieredFetchOutcome outcome;
  final List<FetchTierAttempt> attempts;
  final String? errorMessage;
  final int? httpStatus;
  final bool usedHttpFallback;

  String get tierTrail => attempts.map((a) => a.toString()).join(' → ');
}

enum TieredFetchOutcome {
  success,
  blocked,
  httpError,
  staleCached,
}

/// Fetches Ottawa.ca pages — browser-primary or HTTP-legacy with resilient fallbacks.
class TieredFacilityPageFetcher {
  TieredFacilityPageFetcher({
    OttawaHttpClient? httpClient,
    BrowserFacilityPageFetcher? browserFetcher,
    HtmlSnapshotCache? snapshotCache,
  })  : _httpClient = httpClient ?? OttawaHttpClient(),
        _browserFetcher =
            browserFetcher ?? createBrowserFacilityPageFetcher(),
        _snapshotCache = snapshotCache ?? HtmlSnapshotCache();

  final OttawaHttpClient _httpClient;
  final BrowserFacilityPageFetcher _browserFetcher;
  final HtmlSnapshotCache _snapshotCache;

  BrowserFacilityPageFetcher get browserFetcher => _browserFetcher;

  Future<TieredFetchResult> fetch({
    required String url,
    required String facilityId,
    required int existingCachedSessions,
    bool escalateToBrowser = false,
    SyncEngineMode syncEngineMode = SyncEngineMode.browserPrimary,
  }) async {
    if (syncEngineMode.isBrowserPrimary && _browserFetcher.isAvailable) {
      return _fetchBrowserPrimary(
        url: url,
        facilityId: facilityId,
        existingCachedSessions: existingCachedSessions,
      );
    }

    return _fetchHttpPrimary(
      url: url,
      facilityId: facilityId,
      existingCachedSessions: existingCachedSessions,
      escalateToBrowser: escalateToBrowser || syncEngineMode.isBrowserPrimary,
    );
  }

  Future<TieredFetchResult> _fetchBrowserPrimary({
    required String url,
    required String facilityId,
    required int existingCachedSessions,
  }) async {
    final attempts = <FetchTierAttempt>[];

    try {
      final browserPage = await _browserFetcher.fetchRequest(
        BrowserFetchRequest(
          url: url,
          facilityId: facilityId,
          timeoutMs: 30000,
        ),
      );

      if (browserPage != null &&
          !BlockedPageDetector.isBlockedPage(browserPage.html)) {
        if (browserPage.scheduleTableCount == 0 &&
            existingCachedSessions > 0 &&
            !BlockedPageDetector.check(browserPage.html).hasScheduleTables) {
          attempts.add(FetchTierAttempt(
            tier: FacilityFetchTier.browser,
            outcome: 'empty_tables',
            detail: 'dom=${browserPage.domSizeBytes}',
          ));
        } else {
          attempts.add(FetchTierAttempt(
            tier: FacilityFetchTier.browser,
            outcome: 'ok',
            httpStatus: browserPage.statusCode,
            detail:
                'engine=${browserPage.syncEngineLabel ?? _browserFetcher.engineLabel} '
                'dom=${browserPage.domSizeBytes} '
                'tables=${browserPage.scheduleTableCount} '
                '${browserPage.loadTimeMs}ms',
          ));
          return TieredFetchResult(
            outcome: TieredFetchOutcome.success,
            attempts: attempts,
            page: browserPage,
            httpStatus: browserPage.statusCode,
          );
        }
      }

      if (browserPage != null) {
        final blockedCheck = BlockedPageDetector.check(browserPage.html);
        attempts.add(FetchTierAttempt(
          tier: FacilityFetchTier.browser,
          outcome: blockedCheck.isBlocked ? 'blocked' : 'empty',
          httpStatus: browserPage.statusCode,
          detail: blockedCheck.signaturesMatched.join(',') +
              (browserPage.domSizeBytes != null
                  ? ' dom=${browserPage.domSizeBytes}'
                  : ''),
        ));
      } else {
        attempts.add(FetchTierAttempt(
          tier: FacilityFetchTier.browser,
          outcome: 'empty',
          detail: _browserFetcher.engineLabel,
        ));
      }
    } catch (e, st) {
      attempts.add(FetchTierAttempt(
        tier: FacilityFetchTier.browser,
        outcome: 'error',
        detail: e.toString(),
      ));
      appLogger.w('Browser-primary fetch failed', error: e, stackTrace: st);
    }

    appLogger.i(
      '[fetch] Browser primary failed for $facilityId — trying HTTP fallback',
    );

    final httpResult = await _tryHttpFetch(
      url: url,
      facilityId: facilityId,
      attempts: attempts,
    );
    if (httpResult != null) {
      return TieredFetchResult(
        outcome: TieredFetchOutcome.success,
        attempts: attempts,
        page: httpResult.copyWith(usedHttpFallback: true),
        httpStatus: httpResult.statusCode,
        usedHttpFallback: true,
      );
    }

    return _finishWithCacheFallback(
      attempts: attempts,
      facilityId: facilityId,
      existingCachedSessions: existingCachedSessions,
      errorMessage: 'Browser and HTTP fetch blocked',
    );
  }

  Future<TieredFetchResult> _fetchHttpPrimary({
    required String url,
    required String facilityId,
    required int existingCachedSessions,
    required bool escalateToBrowser,
  }) async {
    final attempts = <FetchTierAttempt>[];

    try {
      final response = await _httpClient.fetchFacilityPage(url);
      if (!BlockedPageDetector.isBlockedPage(response.body)) {
        attempts.add(FetchTierAttempt(
          tier: FacilityFetchTier.http,
          outcome: 'ok',
          httpStatus: response.statusCode,
        ));
        return TieredFetchResult(
          outcome: TieredFetchOutcome.success,
          attempts: attempts,
          page: FacilityPageFetchResult(
            html: response.body,
            statusCode: response.statusCode,
            finalUrl: response.request?.url.toString() ?? url,
            contentType: response.headers['content-type'],
            tier: FacilityFetchTier.http,
            syncEngineLabel: 'HTTP',
          ),
          httpStatus: response.statusCode,
        );
      }

      final blockedCheck = BlockedPageDetector.check(response.body);
      attempts.add(FetchTierAttempt(
        tier: FacilityFetchTier.http,
        outcome: 'blocked',
        httpStatus: response.statusCode,
        detail: blockedCheck.signaturesMatched.join(','),
      ));
      appLogger.i(
        '[fetch] Tier 1 blocked for $facilityId — ${escalateToBrowser ? 'escalating to browser' : 'using cache/backoff'}',
      );
      if (!escalateToBrowser) {
        return _finishWithCacheFallback(
          attempts: attempts,
          facilityId: facilityId,
          existingCachedSessions: existingCachedSessions,
          httpStatus: 200,
          errorMessage: 'HTTP blocked — skipped browser escalation',
        );
      }
    } on ScrapeHttpException catch (e) {
      attempts.add(FetchTierAttempt(
        tier: FacilityFetchTier.http,
        outcome: 'http_error',
        httpStatus: e.statusCode,
        detail: e.toString(),
      ));
      if (e.statusCode != 403 && e.statusCode != 429) {
        return _finishWithCacheFallback(
          attempts: attempts,
          facilityId: facilityId,
          existingCachedSessions: existingCachedSessions,
          httpStatus: e.statusCode,
          errorMessage: e.toString(),
          preferHttpError: true,
        );
      }
      if (!escalateToBrowser) {
        return _finishWithCacheFallback(
          attempts: attempts,
          facilityId: facilityId,
          existingCachedSessions: existingCachedSessions,
          httpStatus: e.statusCode,
          errorMessage: e.toString(),
        );
      }
      appLogger.i(
        '[fetch] Tier 1 HTTP ${e.statusCode} for $facilityId — escalating to browser',
      );
    } catch (e) {
      attempts.add(FetchTierAttempt(
        tier: FacilityFetchTier.http,
        outcome: 'error',
        detail: e.toString(),
      ));
    }

    if (escalateToBrowser && _browserFetcher.isAvailable) {
      try {
        final browserPage = await _browserFetcher.fetchRequest(
          BrowserFetchRequest(url: url, facilityId: facilityId),
        );
        if (browserPage != null &&
            !BlockedPageDetector.isBlockedPage(browserPage.html)) {
          attempts.add(FetchTierAttempt(
            tier: FacilityFetchTier.browser,
            outcome: 'ok',
            httpStatus: 200,
            detail: browserPage.syncEngineLabel,
          ));
          return TieredFetchResult(
            outcome: TieredFetchOutcome.success,
            attempts: attempts,
            page: browserPage,
            httpStatus: browserPage.statusCode,
          );
        }

        if (browserPage != null) {
          final blockedCheck = BlockedPageDetector.check(browserPage.html);
          attempts.add(FetchTierAttempt(
            tier: FacilityFetchTier.browser,
            outcome: 'blocked',
            httpStatus: browserPage.statusCode,
            detail: blockedCheck.signaturesMatched.join(','),
          ));
        } else {
          attempts.add(FetchTierAttempt(
            tier: FacilityFetchTier.browser,
            outcome: 'empty',
          ));
        }
      } catch (e, st) {
        attempts.add(FetchTierAttempt(
          tier: FacilityFetchTier.browser,
          outcome: 'error',
          detail: e.toString(),
        ));
        appLogger.w('Tier 2 browser fetch failed', error: e, stackTrace: st);
      }
    } else if (escalateToBrowser) {
      attempts.add(const FetchTierAttempt(
        tier: FacilityFetchTier.browser,
        outcome: 'unavailable',
      ));
    }

    return _finishWithCacheFallback(
      attempts: attempts,
      facilityId: facilityId,
      existingCachedSessions: existingCachedSessions,
    );
  }

  Future<FacilityPageFetchResult?> _tryHttpFetch({
    required String url,
    required String facilityId,
    required List<FetchTierAttempt> attempts,
  }) async {
    try {
      final response = await _httpClient.fetchFacilityPage(url);
      if (!BlockedPageDetector.isBlockedPage(response.body)) {
        attempts.add(FetchTierAttempt(
          tier: FacilityFetchTier.http,
          outcome: 'ok_fallback',
          httpStatus: response.statusCode,
        ));
        return FacilityPageFetchResult(
          html: response.body,
          statusCode: response.statusCode,
          finalUrl: response.request?.url.toString() ?? url,
          contentType: response.headers['content-type'],
          tier: FacilityFetchTier.http,
          syncEngineLabel: 'HTTP',
          usedHttpFallback: true,
        );
      }
      attempts.add(FetchTierAttempt(
        tier: FacilityFetchTier.http,
        outcome: 'blocked_fallback',
        httpStatus: response.statusCode,
      ));
    } on ScrapeHttpException catch (e) {
      attempts.add(FetchTierAttempt(
        tier: FacilityFetchTier.http,
        outcome: 'http_error_fallback',
        httpStatus: e.statusCode,
      ));
    } catch (e) {
      attempts.add(FetchTierAttempt(
        tier: FacilityFetchTier.http,
        outcome: 'error_fallback',
        detail: e.toString(),
      ));
    }
    return null;
  }

  Future<TieredFetchResult> _finishWithCacheFallback({
    required List<FetchTierAttempt> attempts,
    required String facilityId,
    required int existingCachedSessions,
    int? httpStatus,
    String? errorMessage,
    bool preferHttpError = false,
  }) async {
    final snapshotHtml = await _snapshotCache.loadLatestHtml(facilityId);
    if (snapshotHtml != null &&
        !BlockedPageDetector.isBlockedPage(snapshotHtml)) {
      attempts.add(const FetchTierAttempt(
        tier: FacilityFetchTier.cacheSnapshot,
        outcome: 'ok',
      ));
      return TieredFetchResult(
        outcome: TieredFetchOutcome.success,
        attempts: attempts,
        page: FacilityPageFetchResult(
          html: snapshotHtml,
          statusCode: 200,
          finalUrl: 'cache-snapshot://$facilityId',
          contentType: 'text/html',
          tier: FacilityFetchTier.cacheSnapshot,
        ),
        httpStatus: 200,
      );
    }

    if (snapshotHtml != null) {
      attempts.add(const FetchTierAttempt(
        tier: FacilityFetchTier.cacheSnapshot,
        outcome: 'blocked_snapshot',
      ));
    } else {
      attempts.add(const FetchTierAttempt(
        tier: FacilityFetchTier.cacheSnapshot,
        outcome: 'missing',
      ));
    }

    if (existingCachedSessions > 0) {
      attempts.add(FetchTierAttempt(
        tier: FacilityFetchTier.cacheDb,
        outcome: 'ok',
        detail: '$existingCachedSessions sessions',
      ));
      return TieredFetchResult(
        outcome: TieredFetchOutcome.staleCached,
        attempts: attempts,
        httpStatus: httpStatus,
        errorMessage: errorMessage,
      );
    }

    attempts.add(const FetchTierAttempt(
      tier: FacilityFetchTier.cacheDb,
      outcome: 'empty',
    ));

    if (preferHttpError) {
      return TieredFetchResult(
        outcome: TieredFetchOutcome.httpError,
        attempts: attempts,
        httpStatus: httpStatus,
        errorMessage: errorMessage,
      );
    }

    return TieredFetchResult(
      outcome: TieredFetchOutcome.blocked,
      attempts: attempts,
      httpStatus: httpStatus ?? 200,
      errorMessage: errorMessage ?? 'All fetch tiers blocked',
    );
  }
}

extension _FacilityPageFetchResultCopy on FacilityPageFetchResult {
  FacilityPageFetchResult copyWith({bool? usedHttpFallback}) {
    return FacilityPageFetchResult(
      html: html,
      statusCode: statusCode,
      finalUrl: finalUrl,
      tier: tier,
      contentType: contentType,
      domSizeBytes: domSizeBytes,
      loadTimeMs: loadTimeMs,
      scheduleTableCount: scheduleTableCount,
      syncEngineLabel: syncEngineLabel,
      usedHttpFallback: usedHttpFallback ?? this.usedHttpFallback,
    );
  }
}

/// Adapts [FacilityPageFetchResult] to [http.Response] for legacy parse path.
http.Response toHttpResponse(FacilityPageFetchResult page) {
  return http.Response(
    page.html,
    page.statusCode,
    request: http.Request('GET', Uri.parse(page.finalUrl)),
    headers: {
      if (page.contentType != null) 'content-type': page.contentType!,
    },
  );
}
