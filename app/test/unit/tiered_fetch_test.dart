import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:ottawa_swim_finder/data/services/blocked_page_detector.dart';
import 'package:ottawa_swim_finder/data/services/fetch/browser_facility_page_fetcher.dart';
import 'package:ottawa_swim_finder/data/services/fetch/tiered_facility_page_fetcher.dart';
import 'package:ottawa_swim_finder/data/services/ottawa_http_client.dart';
import 'package:ottawa_swim_finder/data/services/scrape_http_exception.dart';
import 'package:ottawa_swim_finder/domain/entities/facility_fetch_tier.dart';

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

  setUp(() {
    httpClient = _MockHttpClient();
    browserFetcher = _MockBrowserFetcher();
    fetcher = TieredFacilityPageFetcher(
      httpClient: httpClient,
      browserFetcher: browserFetcher,
    );
  });

  test('tier 1 returns valid HTML without browser escalation', () async {
    when(() => httpClient.fetchFacilityPage(any())).thenAnswer(
      (_) async => http.Response(_validTableHtml, 200),
    );

    final result = await fetcher.fetch(
      url: 'https://ottawa.ca/test',
      facilityId: 'test-facility',
      existingCachedSessions: 0,
    );

    expect(result.outcome, TieredFetchOutcome.success);
    expect(result.page?.tier, FacilityFetchTier.http);
    verify(() => httpClient.fetchFacilityPage(any())).called(1);
    verifyNever(() => browserFetcher.fetch(any()));
  });

  test('tier 1 blocked escalates to tier 2 browser when enabled', () async {
    when(() => httpClient.fetchFacilityPage(any())).thenAnswer(
      (_) async => http.Response(_blockedHtml, 200),
    );
    when(() => browserFetcher.isAvailable).thenReturn(true);
    when(() => browserFetcher.fetch(any())).thenAnswer(
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
    );

    expect(result.outcome, TieredFetchOutcome.success);
    expect(result.page?.tier, FacilityFetchTier.browser);
    expect(
      result.attempts.any((a) => a.tier == FacilityFetchTier.http && a.outcome == 'blocked'),
      isTrue,
    );
    verify(() => browserFetcher.fetch(any())).called(1);
  });

  test('tier 1 blocked skips browser by default', () async {
    when(() => httpClient.fetchFacilityPage(any())).thenAnswer(
      (_) async => http.Response(_blockedHtml, 200),
    );
    when(() => browserFetcher.isAvailable).thenReturn(true);

    final result = await fetcher.fetch(
      url: 'https://ottawa.ca/test',
      facilityId: 'test-facility',
      existingCachedSessions: 0,
    );

    expect(result.outcome, TieredFetchOutcome.blocked);
    verifyNever(() => browserFetcher.fetch(any()));
  });

  test('tier 3 uses cached DB when all fetch tiers blocked', () async {
    when(() => httpClient.fetchFacilityPage(any())).thenAnswer(
      (_) async => http.Response(_blockedHtml, 200),
    );
    when(() => browserFetcher.isAvailable).thenReturn(true);
    when(() => browserFetcher.fetch(any())).thenAnswer(
      (_) async => const FacilityPageFetchResult(
        html: _blockedHtml,
        statusCode: 200,
        finalUrl: 'https://ottawa.ca/test',
        tier: FacilityFetchTier.browser,
      ),
    );

    final result = await fetcher.fetch(
      url: 'https://ottawa.ca/test',
      facilityId: 'test-facility',
      existingCachedSessions: 42,
      escalateToBrowser: true,
    );

    expect(result.outcome, TieredFetchOutcome.staleCached);
    expect(result.page, isNull);
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
