import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'package:ottawa_swim_finder/core/constants/http_constants.dart';
import 'package:ottawa_swim_finder/data/services/blocked_page_detector.dart';
import 'package:ottawa_swim_finder/data/services/fetch/create_browser_fetcher.dart';
import 'package:ottawa_swim_finder/data/services/fetch/tiered_facility_page_fetcher.dart';

/// Tiered fetch diagnostic — run: dart run tool/sync_diagnostic_probe.dart
Future<void> main() async {
  const facilities = [
    ('jack-purcell-community-centre', 'Jack Purcell'),
    ('plant-recreation-centre', 'Plant'),
    ('walter-baker-sports-centre', 'Walter Baker'),
  ];

  final fetcher = TieredFacilityPageFetcher(
    browserFetcher: createBrowserFacilityPageFetcher(),
  );

  for (final (id, name) in facilities) {
    final url =
        'https://ottawa.ca/en/recreation-and-parks/facilities/place-listing/$id';
    final result = await fetcher.fetch(
      url: url,
      facilityId: id,
      existingCachedSessions: 0,
    );

    final page = result.page;
    final blocked = page != null
        ? BlockedPageDetector.check(page.html)
        : null;
    final fingerprint = page != null
        ? sha256
            .convert(utf8.encode(
              page.html.length > 2000
                  ? page.html.substring(0, 2000)
                  : page.html,
            ))
            .toString()
            .substring(0, 16)
        : '—';

    // ignore: avoid_print
    print('Facility: $name');
    // ignore: avoid_print
    print('Outcome: ${result.outcome.name}');
    // ignore: avoid_print
    print('Tier trail: ${result.tierTrail}');
    // ignore: avoid_print
    print('HTTP: ${result.httpStatus ?? page?.statusCode ?? '—'}');
    // ignore: avoid_print
    print('Fetch tier: ${page?.tier.label ?? '—'}');
    // ignore: avoid_print
    print('User-Agent: ${HttpConstants.userAgent.substring(0, 40)}...');
    // ignore: avoid_print
    print('Blocked: ${blocked?.isBlocked ?? 'n/a'}');
    // ignore: avoid_print
    print('HTML fingerprint: $fingerprint');
    // ignore: avoid_print
    print('---');
  }
}
