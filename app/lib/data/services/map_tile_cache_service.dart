import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';

class MapCacheInfo {
  const MapCacheInfo({
    required this.tileCount,
    required this.sizeKb,
    required this.hits,
    required this.misses,
  });

  final int tileCount;
  final double sizeKb;
  final int hits;
  final int misses;

  String get sizeLabel {
    if (sizeKb < 1024) return '${sizeKb.toStringAsFixed(0)} KB';
    return '${(sizeKb / 1024).toStringAsFixed(1)} MB';
  }
}

class MapTileCacheService {
  static const storeName = 'ottawaMapStore';

  FMTCStore get _store => FMTCStore(storeName);

  FMTCTileProvider get tileProvider => FMTCTileProvider(
        stores: const {storeName: BrowseStoreStrategy.readUpdateCreate},
      );

  TileLayer get tileLayer => TileLayer(
        urlTemplate: AppConstants.osmTileUrlTemplate,
        userAgentPackageName: AppConstants.osmUserAgentPackage,
        tileProvider: tileProvider,
      );

  Future<void> initialize() async {
    await FMTCObjectBoxBackend().initialise();
    final ready = await _store.manage.ready;
    if (!ready) {
      await _store.manage.create();
    }
    await _store.metadata.set(key: 'urlTemplate', value: AppConstants.osmTileUrlTemplate);
    appLogger.i('Map tile cache initialized');
  }

  Future<MapCacheInfo> getCacheInfo() async {
    final stats = await _store.stats.all;
    return MapCacheInfo(
      tileCount: stats.length,
      sizeKb: stats.size,
      hits: stats.hits,
      misses: stats.misses,
    );
  }

  /// Pre-download Ottawa map tiles for offline use (zoom 10–13).
  /// User-initiated; respects rate limits and skips existing tiles.
  Stream<double> warmCacheForOttawa() async* {
    final bounds = LatLngBounds(
      const LatLng(45.25, -76.05),
      const LatLng(45.55, -75.35),
    );

    final region = RectangleRegion(bounds).toDownloadable(
      minZoom: 10,
      maxZoom: 13,
      options: TileLayer(
        urlTemplate: AppConstants.osmTileUrlTemplate,
        userAgentPackageName: AppConstants.osmUserAgentPackage,
      ),
    );

    final streams = _store.download.startForeground(
      region: region,
      parallelThreads: 2,
      skipExistingTiles: true,
      skipSeaTiles: true,
      rateLimit: 4,
    );

    await for (final progress in streams.downloadProgress) {
      yield progress.percentageProgress / 100;
      if (progress.percentageProgress >= 100) break;
    }
  }

  Future<void> clearCache() async {
    await _store.manage.delete();
    await _store.manage.create();
    await _store.metadata.set(key: 'urlTemplate', value: AppConstants.osmTileUrlTemplate);
  }
}
