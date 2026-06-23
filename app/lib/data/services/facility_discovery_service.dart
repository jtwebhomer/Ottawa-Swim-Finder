import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html_parser;

import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/facility_type.dart';
import '../../domain/entities/sync_status.dart';
import 'fetch/tiered_facility_page_fetcher.dart';
import 'facility_slug_registry.dart';
import 'ottawa_http_client.dart';

/// A facility row parsed from Ottawa's indoor pools listing page.
class DiscoveredFacilityRow {
  const DiscoveredFacilityRow({
    required this.name,
    required this.address,
    required this.region,
    required this.slug,
    required this.slugResolution,
  });

  final String name;
  final String address;
  final String region;
  final String slug;
  final String slugResolution;

  String get url =>
      '${AppConstants.ottawaBaseUrl}/en/recreation-and-parks/facilities/place-listing/$slug';
}

/// Parses Ottawa aquatic facility listing pages and resolves slugs.
class FacilityDiscoveryService {
  FacilityDiscoveryService({
    TieredFacilityPageFetcher? fetcher,
    OttawaHttpClient? httpClient,
  }) : _fetcher = fetcher,
       _httpClient = httpClient ?? OttawaHttpClient();

  final TieredFacilityPageFetcher? _fetcher;
  final OttawaHttpClient _httpClient;

  Future<List<DiscoveredFacilityRow>> discoverIndoorPoolsFromSource({
    bool escalateToBrowser = false,
  }) async {
    final html = await _fetchListingHtml(
      AppConstants.indoorPoolsUrl,
      escalateToBrowser: escalateToBrowser,
    );
    if (html == null) return [];
    return _parseIndoorListingHtml(html);
  }

  List<DiscoveredFacilityRow> _parseIndoorListingHtml(String html) {
    final document = html_parser.parse(html);
    final facilities = <DiscoveredFacilityRow>[];
    var currentRegion = 'unknown';
    final seenSlugs = <String>{};

    for (final element in document.querySelectorAll('h3, li')) {
      if (element.localName == 'h3') {
        final text = element.text.trim().toLowerCase();
        if (const {'central', 'east', 'south', 'west'}.contains(text)) {
          currentRegion = text;
        }
        continue;
      }

      final text = element.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (!text.contains(',')) continue;

      final match = RegExp(r'^(.+?),\s*(.+)$').firstMatch(text);
      if (match == null) continue;

      final name = match.group(1)!.trim();
      final address = match.group(2)!.trim();
      final slug = FacilitySlugRegistry.slugForName(name);
      if (slug == null || slug.isEmpty) {
        appLogger.w('[discovery] No slug for: $name');
        continue;
      }
      if (seenSlugs.contains(slug)) {
        appLogger.w('[discovery] Duplicate slug $slug for $name');
        continue;
      }
      seenSlugs.add(slug);

      final resolution = FacilitySlugRegistry.fragments.entries
              .any((e) => name.toLowerCase().contains(e.key))
          ? 'registry'
          : 'slugify';

      facilities.add(
        DiscoveredFacilityRow(
          name: name,
          address: address,
          region: currentRegion,
          slug: slug,
          slugResolution: resolution,
        ),
      );
    }

    appLogger.i('[discovery] Parsed ${facilities.length} indoor facilities');
    return facilities;
  }

  /// Test hook for HTML parsing without network.
  List<DiscoveredFacilityRow> parseIndoorListingForTest(String html) =>
      _parseIndoorListingHtml(html);

  Future<String?> _fetchListingHtml(
    String url, {
    bool escalateToBrowser = false,
  }) async {
    if (_fetcher != null) {
      final result = await _fetcher.fetch(
        url: url,
        facilityId: 'facility-discovery',
        existingCachedSessions: 0,
        escalateToBrowser: escalateToBrowser,
      );
      return result.page?.html;
    }

    try {
      final response = await _httpClient.fetchFacilityPage(url);
      return response.body;
    } catch (e) {
      appLogger.w('[discovery] Failed to fetch listing', error: e);
      return null;
    }
  }

  Future<List<Facility>> loadCanonicalFacilities() async {
    final jsonStr =
        await rootBundle.loadString('assets/facilities_canonical.json');
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    final rows = (data['facilities'] as List).cast<Map<String, dynamic>>();

    return rows.map((row) {
      final id = row['id'] as String;
      final name = row['name'] as String;
      final type = FacilityType.inferFromIdAndName(
        id: id,
        name: name,
        explicit: row['facility_type'] as String?,
      );
      final scheduleMode = FacilityScheduleMode.fromStorage(
            row['schedule_mode'] as String?,
          ) ??
          FacilityScheduleMode.forType(type);

      return Facility(
        id: id,
        name: name,
        address: row['address'] as String?,
        latitude: (row['latitude'] as num?)?.toDouble(),
        longitude: (row['longitude'] as num?)?.toDouble(),
        region: row['region'] as String?,
        url:
            '${AppConstants.ottawaBaseUrl}/en/recreation-and-parks/facilities/place-listing/$id',
        facilityType: type,
        scheduleMode: scheduleMode,
        metadataJson: row['notes'] != null
            ? json.encode({'notes': row['notes']})
            : null,
      );
    }).toList();
  }

  Facility mergeDiscoveredWithCanonical({
    required DiscoveredFacilityRow discovered,
    Facility? canonical,
  }) {
    final type = canonical?.facilityType ??
        FacilityType.inferFromIdAndName(
          id: discovered.slug,
          name: discovered.name,
        );
    final scheduleMode =
        canonical?.scheduleMode ?? FacilityScheduleMode.forType(type);

    return Facility(
      id: discovered.slug,
      name: discovered.name,
      address: discovered.address,
      latitude: canonical?.latitude,
      longitude: canonical?.longitude,
      region: discovered.region,
      url: discovered.url,
      facilityType: type,
      scheduleMode: scheduleMode,
      contentHash: canonical?.contentHash,
      lastUpdated: canonical?.lastUpdated,
      lastSuccessfulSyncAt: canonical?.lastSuccessfulSyncAt,
      syncStatus: canonical?.syncStatus ?? FacilitySyncStatus.ok,
      isFavorite: canonical?.isFavorite ?? false,
      metadataJson: canonical?.metadataJson,
    );
  }
}
