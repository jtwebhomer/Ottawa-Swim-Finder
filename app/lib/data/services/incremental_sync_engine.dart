import '../../core/logging/app_logger.dart';
import '../../domain/entities/facility_priority.dart';
import '../../domain/entities/sync_location_context.dart';
import '../../domain/entities/sync_progress.dart';
import '../scraper/ottawa_scraper.dart';
import 'location_service.dart';
import 'seed_database_service.dart';
import 'sync_service.dart';

enum IncrementalSyncPhase {
  seedValidation,
  immediateFacilities,
  expansionFacilities,
  backgroundFacilities,
}

/// Phased background sync: seed → immediate → expansion → idle background.
class IncrementalSyncEngine {
  IncrementalSyncEngine({
    required SeedDatabaseService seedService,
    required SyncService syncService,
    required LocationService locationService,
  })  : _seedService = seedService,
        _syncService = syncService,
        _locationService = locationService;

  final SeedDatabaseService _seedService;
  final SyncService _syncService;
  final LocationService _locationService;

  Future<IncrementalSyncResult> runBackgroundSync({
    bool force = false,
    double? userLat,
    double? userLng,
    SyncProgressCallback? onProgress,
    Future<void> Function(SmartSyncPhase phase)? onPhaseComplete,
  }) async {
    appLogger.i('[incremental-sync] Phase 0: seed validation');
    final seedResult = await _seedService.ensureSeeded();
    final anchor = await _resolveLocation(userLat: userLat, userLng: userLng);

    appLogger.i('[incremental-sync] Smart phased sync (anchor=${anchor.usesDeviceLocation ? "gps" : "fallback"})');
    final syncResult = await _syncService.syncIfNeeded(
      force: force,
      anchor: anchor,
      onProgress: onProgress,
      onPhaseComplete: onPhaseComplete,
    );

    return IncrementalSyncResult(
      seedResult: seedResult,
      syncResult: syncResult,
      phasesCompleted: const [
        IncrementalSyncPhase.seedValidation,
        IncrementalSyncPhase.immediateFacilities,
        IncrementalSyncPhase.expansionFacilities,
        IncrementalSyncPhase.backgroundFacilities,
      ],
      anchor: anchor,
    );
  }

  Future<IncrementalSyncResult> runManualSync({
    double? userLat,
    double? userLng,
    SyncProgressCallback? onProgress,
    Future<void> Function(SmartSyncPhase phase)? onPhaseComplete,
  }) async {
    final anchor = await _resolveLocation(userLat: userLat, userLng: userLng);
    final syncResult = await _syncService.forceSync(
      onProgress: onProgress,
      anchor: anchor,
      onPhaseComplete: onPhaseComplete,
    );

    return IncrementalSyncResult(
      seedResult: const SeedLoadResult(
        loaded: false,
        facilityCount: 0,
        scheduleCount: 0,
      ),
      syncResult: syncResult,
      phasesCompleted: const [
        IncrementalSyncPhase.immediateFacilities,
        IncrementalSyncPhase.expansionFacilities,
        IncrementalSyncPhase.backgroundFacilities,
      ],
      anchor: anchor,
    );
  }

  Future<SyncLocationContext> _resolveLocation({
    double? userLat,
    double? userLng,
  }) async {
    if (userLat != null && userLng != null) {
      return SyncLocationContext.fromDevice(
        latitude: userLat,
        longitude: userLng,
      );
    }

    final position = await _locationService.getCurrentPosition();
    if (position != null) {
      return SyncLocationContext.fromDevice(
        latitude: position.latitude,
        longitude: position.longitude,
      );
    }

    return SyncLocationContext.fallback();
  }
}

class IncrementalSyncResult {
  const IncrementalSyncResult({
    required this.seedResult,
    required this.syncResult,
    required this.phasesCompleted,
    required this.anchor,
  });

  final SeedLoadResult seedResult;
  final SyncResult syncResult;
  final List<IncrementalSyncPhase> phasesCompleted;
  final SyncLocationContext anchor;
}
