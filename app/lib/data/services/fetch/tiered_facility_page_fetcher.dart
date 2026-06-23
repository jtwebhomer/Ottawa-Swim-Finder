import 'package:http/http.dart' as http;

import '../../../core/logging/app_logger.dart';
import '../../../domain/entities/facility_fetch_tier.dart';
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
  });

  final FacilityPageFetchResult? page;
  final TieredFetchOutcome outcome;
  final List<FetchTierAttempt> attempts;
  final String? errorMessage;
  final int? httpStatus;

  String get tierTrail => attempts.map((a) => a.toString()).join(' → ');
}

enum TieredFetchOutcome {
  success,
  blocked,
  httpError,
  staleCached,
}

/// HTTP → Browser → Cache snapshot/DB fallback orchestrator.
class TieredFacilityPageFetcher {
  TieredFacilityPageFetcher({
    OttawaHttpClient? httpClient,
    BrowserFacilityPageFetcher? browserFetcher,
    HtmlSnapshotCache? snapshotCache,
  })  : _httpClient = httpClient ??
            OttawaHttpClient(
              maxRetries: 1,
              interRequestDelayMs: 0,
              baseDelayMs: 0,
            ),
        _browserFetcher =
            browserFetcher ?? createBrowserFacilityPageFetcher(),
        _snapshotCache = snapshotCache ?? HtmlSnapshotCache();

  final OttawaHttpClient _httpClient;
  final BrowserFacilityPageFetcher _browserFetcher;
  final HtmlSnapshotCache _snapshotCache;

  Future<TieredFetchResult> fetch({
    required String url,
    required String facilityId,
    required int existingCachedSessions,
  }) async {
    final attempts = <FetchTierAttempt>[];

    // --- Tier 1: fast HTTP ---
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
        '[fetch] Tier 1 blocked for $facilityId — escalating to browser',
      );
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

    // --- Tier 2: JS-enabled browser ---
    if (_browserFetcher.isAvailable) {
      try {
        final browserPage = await _browserFetcher.fetch(url);
        if (browserPage != null &&
            !BlockedPageDetector.isBlockedPage(browserPage.html)) {
          attempts.add(const FetchTierAttempt(
            tier: FacilityFetchTier.browser,
            outcome: 'ok',
            httpStatus: 200,
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
          attempts.add(const FetchTierAttempt(
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
    } else {
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

  Future<TieredFetchResult> _finishWithCacheFallback({
    required List<FetchTierAttempt> attempts,
    required String facilityId,
    required int existingCachedSessions,
    int? httpStatus,
    String? errorMessage,
    bool preferHttpError = false,
  }) async {
    // --- Tier 3a: replay latest HTML snapshot ---
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

    // --- Tier 3b: preserve DB cache ---
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
