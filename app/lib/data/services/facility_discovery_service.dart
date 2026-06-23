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

  Future<List<DiscoveredFacilityRow>> discoverOutdoorPoolsFromSource({
    bool escalateToBrowser = false,
  }) async {
    final html = await _fetchListingHtml(
      AppConstants.outdoorPoolsUrl,
      escalateToBrowser: escalateToBrowser,
    );
    if (html == null) return [];
    return _parseOutdoorListingHtml(html);
  }

  List<DiscoveredFacilityRow> _parseOutdoorListingHtml(String html) {
    final document = html_parser.parse(html);
    final facilities = <DiscoveredFacilityRow>[];
    final seenSlugs = <String>{};

    for (final element in document.querySelectorAll('li, p')) {
      final text = element.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (!text.contains(',')) continue;

      final match = RegExp(r'^(.+?),\s*(.+)$').firstMatch(text);
      if (match == null) continue;

      final name = match.group(1)!.trim();
      if (!name.toLowerCase().contains('pool') &&
          !name.toLowerCase().contains('splash')) {
        continue;
      }

      final slug = FacilitySlugRegistry.slugForName(name);
      if (slug == null || slug.isEmpty || seenSlugs.contains(slug)) continue;
      seenSlugs.add(slug);

      facilities.add(
        DiscoveredFacilityRow(
          name: name,
          address: match.group(2)!.trim(),
          region: 'outdoor',
          slug: slug,
          slugResolution: 'outdoor-listing',
        ),
      );
    }

    appLogger.i('[discovery] Parsed ${facilities.length} outdoor facilities');
    return facilities;
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
    String jsonStr;
    try {
      jsonStr = await rootBundle.loadString('assets/facilities_registry.json');
    } catch (_) {
      jsonStr = await rootBundle.loadString('assets/facilities_canonical.json');
    }
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    final rows = (data['facilities'] as List).cast<Map<String, dynamic>>();

    return rows.map((row) {
      final id = row['id'] as String;
      final name = row['name'] as String;
      final type = FacilityType.inferFromIdAndName(
        id: id,
        name: name,
        explicit: (row['facility_type'] ?? row['type']) as String?,
      );
      final dataModel = FacilityDataModel.fromStorage(
            row['data_model'] as String?,
          ) ??
          FacilityDataModel.forType(
            type,
            hasSwimSchedule: row['has_swim_schedule'] as bool?,
          );
      final scheduleMode = FacilityScheduleMode.fromStorage(
            row['schedule_mode'] as String?,
          ) ??
          FacilityScheduleMode.forDataModel(dataModel);

      return Facility(
        id: id,
        name: name,
        address: row['address'] as String?,
        latitude: ((row['latitude'] ?? row['lat']) as num?)?.toDouble(),
        longitude: ((row['longitude'] ?? row['lng']) as num?)?.toDouble(),
        region: row['region'] as String?,
        url:
            '${AppConstants.ottawaBaseUrl}/en/recreation-and-parks/facilities/place-listing/$id',
        facilityType: type,
        dataModel: dataModel,
        displayStatus: FacilityDisplayStatus.defaultFor(dataModel),
        scheduleMode: scheduleMode,
        metadataJson: () {
          final meta = <String, dynamic>{
            if (row['notes'] != null) 'notes': row['notes'],
            if (row['season'] != null) 'season': row['season'],
          };
          return meta.isEmpty ? null : json.encode(meta);
        }(),
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
        canonical?.scheduleMode ??
            FacilityScheduleMode.forDataModel(
              FacilityDataModel.forType(type),
            );

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
