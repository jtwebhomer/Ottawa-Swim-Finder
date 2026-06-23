import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:ottawa_swim_finder/data/services/blocked_page_detector.dart';
import 'package:ottawa_swim_finder/data/services/fetch/browser_facility_page_fetcher.dart';
import 'package:ottawa_swim_finder/data/services/fetch/tiered_facility_page_fetcher.dart';
import 'package:ottawa_swim_finder/data/services/ottawa_http_client.dart';
import 'package:ottawa_swim_finder/domain/entities/facility_fetch_tier.dart';
import 'package:ottawa_swim_finder/domain/entities/sync_engine_mode.dart';

class _MockHttpClient extends Mock implements OttawaHttpClient {}

class _MockBrowserFetcher extends Mock implements BrowserFacilityPageFetcher {}

const _validTableHtml = '''
<table><caption>Pool swim - June 1 to August 31</caption>
<thead><tr><th></th><th>Monday</th></tr></thead>
<tbody><tr><th>Lane swim</th><td>8 - 9 am</td></tr></tbody></table>
''';

const _blockedHtml = '<html><body>Pardon Our Interruption</body></html>';

void main() {
  late _MockHttpClient httpClient;
  late _MockBrowserFetcher browserFetcher;
  late TieredFacilityPageFetcher fetcher;

  setUpAll(() {
    registerFallbackValue(
      const BrowserFetchRequest(url: 'https://ottawa.ca/test'),
    );
  });

  setUp(() {
    httpClient = _MockHttpClient();
    browserFetcher = _MockBrowserFetcher();
    when(() => browserFetcher.engineLabel).thenReturn('PLAYWRIGHT');
    fetcher = TieredFacilityPageFetcher(
      httpClient: httpClient,
      browserFetcher: browserFetcher,
    );
  });

  test('HTTP legacy returns valid HTML without browser', () async {
    when(() => httpClient.fetchFacilityPage(any())).thenAnswer(
      (_) async => http.Response(_validTableHtml, 200),
    );

    final result = await fetcher.fetch(
      url: 'https://ottawa.ca/test',
      facilityId: 'test-facility',
      existingCachedSessions: 0,
      syncEngineMode: SyncEngineMode.httpLegacy,
    );

    expect(result.outcome, TieredFetchOutcome.success);
    expect(result.page?.tier, FacilityFetchTier.http);
    verify(() => httpClient.fetchFacilityPage(any())).called(1);
    verifyNever(() => browserFetcher.fetchRequest(any()));
  });

  test('browser primary uses browser before HTTP', () async {
    when(() => browserFetcher.isAvailable).thenReturn(true);
    when(() => browserFetcher.fetchRequest(any())).thenAnswer(
      (_) async => const FacilityPageFetchResult(
        html: _validTableHtml,
        statusCode: 200,
        finalUrl: 'https://ottawa.ca/test',
        tier: FacilityFetchTier.browser,
        syncEngineLabel: 'PLAYWRIGHT',
        scheduleTableCount: 1,
      ),
    );

    final result = await fetcher.fetch(
      url: 'https://ottawa.ca/test',
      facilityId: 'test-facility',
      existingCachedSessions: 0,
      syncEngineMode: SyncEngineMode.browserPrimary,
    );

    expect(result.outcome, TieredFetchOutcome.success);
    expect(result.page?.tier, FacilityFetchTier.browser);
    verify(() => browserFetcher.fetchRequest(any())).called(1);
    verifyNever(() => httpClient.fetchFacilityPage(any()));
  });

  test('HTTP legacy blocked escalates to browser when enabled', () async {
    when(() => httpClient.fetchFacilityPage(any())).thenAnswer(
      (_) async => http.Response(_blockedHtml, 200),
    );
    when(() => browserFetcher.isAvailable).thenReturn(true);
    when(() => browserFetcher.fetchRequest(any())).thenAnswer(
      (_) async => const FacilityPageFetchResult(
        html: _validTableHtml,
        statusCode: 200,
        finalUrl: 'https://ottawa.ca/test',
        tier: FacilityFetchTier.browser,
      ),
    );

    final result = await fetcher.fetch(
      url: 'https://ottawa.ca/test',
      facilityId: 'test-facility',
      existingCachedSessions: 0,
      escalateToBrowser: true,
      syncEngineMode: SyncEngineMode.httpLegacy,
    );

    expect(result.outcome, TieredFetchOutcome.success);
    expect(result.page?.tier, FacilityFetchTier.browser);
    verify(() => browserFetcher.fetchRequest(any())).called(1);
  });

  test('HTTP legacy blocked skips browser when escalation disabled', () async {
    when(() => httpClient.fetchFacilityPage(any())).thenAnswer(
      (_) async => http.Response(_blockedHtml, 200),
    );
    when(() => browserFetcher.isAvailable).thenReturn(true);

    final result = await fetcher.fetch(
      url: 'https://ottawa.ca/test',
      facilityId: 'test-facility',
      existingCachedSessions: 0,
      syncEngineMode: SyncEngineMode.httpLegacy,
    );

    expect(result.outcome, TieredFetchOutcome.blocked);
    verifyNever(() => browserFetcher.fetchRequest(any()));
  });

  test('browser primary falls back to HTTP then cache', () async {
    when(() => browserFetcher.isAvailable).thenReturn(true);
    when(() => browserFetcher.fetchRequest(any())).thenAnswer(
      (_) async => const FacilityPageFetchResult(
        html: _blockedHtml,
        statusCode: 403,
        finalUrl: 'https://ottawa.ca/test',
        tier: FacilityFetchTier.browser,
      ),
    );
    when(() => httpClient.fetchFacilityPage(any())).thenAnswer(
      (_) async => http.Response(_blockedHtml, 200),
    );

    final result = await fetcher.fetch(
      url: 'https://ottawa.ca/test',
      facilityId: 'test-facility',
      existingCachedSessions: 42,
      syncEngineMode: SyncEngineMode.browserPrimary,
    );

    expect(result.outcome, TieredFetchOutcome.staleCached);
    expect(
      result.attempts.any((a) => a.tier == FacilityFetchTier.cacheDb),
      isTrue,
    );
  });

  test('blocked page detector still flags challenge HTML', () {
    expect(BlockedPageDetector.isBlockedPage(_blockedHtml), isTrue);
    expect(BlockedPageDetector.isBlockedPage(_validTableHtml), isFalse);
  });
}
