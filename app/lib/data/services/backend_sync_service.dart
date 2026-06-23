import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/ottawa_time.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/facility_priority.dart';
import '../../domain/entities/facility_sync_diagnostic.dart';
import '../../domain/entities/facility_type.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/entities/schedule_trust_status.dart';
import '../../domain/entities/sync_location_context.dart';
import '../../domain/entities/sync_progress.dart';
import '../../domain/entities/sync_result.dart';
import '../../domain/entities/sync_status.dart';
import '../../domain/repositories/repositories.dart';
import '../api/api_service.dart';

/// Pulls schedule data from the backend API and caches it in SQLite.
class BackendSyncService {
  BackendSyncService({
    required ApiService api,
    required FacilityRepository facilityRepo,
    required ScheduleRepository scheduleRepo,
    required SettingsRepository settingsRepo,
  })  : _api = api,
        _facilityRepo = facilityRepo,
        _scheduleRepo = scheduleRepo,
        _settingsRepo = settingsRepo;

  final ApiService _api;
  final FacilityRepository _facilityRepo;
  final ScheduleRepository _scheduleRepo;
  final SettingsRepository _settingsRepo;

  Future<SyncResult> syncAll({
    bool force = false,
    bool isOnboarding = false,
    SmartSyncPhase phase = SmartSyncPhase.background,
    SyncLocationContext anchor = const SyncLocationContext(
      latitude: SyncLocationContext.fallbackLatitude,
      longitude: SyncLocationContext.fallbackLongitude,
      usesDeviceLocation: false,
    ),
    SyncProgressCallback? onProgress,
  }) async {
    final scheduleCountBefore = await _scheduleRepo.countAllSchedules();
    final today = OttawaTime.todayDate();

    try {
      final status = await _api.fetchSyncStatus();
      await _settingsRepo.setString(
        AppConstants.settingsBackendFreshnessScore,
        (status.dataFreshnessScore ?? 0).toString(),
      );
      if (status.lastSync != null) {
        await _settingsRepo.setString(
          AppConstants.settingsBackendLastSyncAt,
          status.lastSync.toString(),
        );
      }

      final apiFacilities = await _api.fetchFacilities();
      await _settingsRepo.setString(AppConstants.settingsLastSyncEngine, 'API');

      var updated = 0;
      var skipped = 0;
      var errors = 0;
      var facilitiesParsed = 0;
      final failedNames = <String>[];
      final staleNames = <String>[];
      final diagnostics = <FacilitySyncDiagnostic>[];

      for (final dto in apiFacilities) {
        await _facilityRepo.upsertFacility(_mapFacility(dto));
      }

      final swimFacilities = apiFacilities
          .where((f) => f.hasSwimSchedule ?? f.scheduleMode == 'HAS_SWIM_SCHEDULE')
          .toList();
      final total = swimFacilities.length;

      for (var i = 0; i < swimFacilities.length; i++) {
        final dto = swimFacilities[i];
        onProgress?.call(
          SyncProgress(
            totalFacilities: total,
            updated: updated,
            blocked: 0,
            pending: total - i - 1,
            failed: errors,
            currentFacilityName: dto.name,
            phase: SyncPhase.fetching,
          ),
        );

        try {
          final rows = await _api.fetchSchedules(dto.id);
          if (rows.isEmpty) {
            skipped++;
            if (dto.lastVerified == null) {
              staleNames.add(dto.name);
            }
            continue;
          }

          final entries = rows
              .map((r) => _mapSchedule(dto.id, r))
              .toList(growable: false);
          await _scheduleRepo.replaceSchedulesForFacility(dto.id, entries);

          final verifiedAt = dto.lastVerified ?? DateTime.now().millisecondsSinceEpoch;
          await _facilityRepo.updateSyncMetadata(
            facilityId: dto.id,
            syncStatus: FacilitySyncStatus.ok,
            lastSuccessfulSyncAt: verifiedAt,
            lastUpdated: dto.lastUpdated ?? verifiedAt,
            scheduleTrustStatus: _trustForSource(rows.first.source, rows.first.sourceStatus),
            scheduleSource: _sourceForApi(rows.first.source, rows.first.sourceStatus),
            scheduleVerifiedAt: verifiedAt,
          );

          updated++;
          facilitiesParsed++;
          diagnostics.add(
            FacilitySyncDiagnostic(
              facilityId: dto.id,
              facilityName: dto.name,
              kind: FacilitySyncFailureKind.ok,
              sessionsParsed: entries.length,
              syncEngine: 'API',
            ),
          );
        } catch (e, st) {
          errors++;
          failedNames.add(dto.name);
          appLogger.w('[api-sync] ${dto.id} failed', error: e, stackTrace: st);
          diagnostics.add(
            FacilitySyncDiagnostic(
              facilityId: dto.id,
              facilityName: dto.name,
              kind: FacilitySyncFailureKind.networkFailure,
              detail: e.toString(),
              syncEngine: 'API',
            ),
          );
        }
      }

      final scheduleCountAfter = await _scheduleRepo.countAllSchedules();
      final projectedFuture =
          await _scheduleRepo.countFutureSessions(today);
      final syncStatus = _deriveStatus(
        updated: updated,
        errors: errors,
        total: total,
        scheduleAfter: scheduleCountAfter,
      );
      final successRate =
          total == 0 ? 1.0 : facilitiesParsed / total;

      return SyncResult(
        syncStatus: syncStatus,
        updated: updated,
        skipped: skipped,
        errors: errors,
        scheduleCountBefore: scheduleCountBefore,
        scheduleCountAfter: scheduleCountAfter,
        totalFacilities: total,
        facilitiesParsed: facilitiesParsed,
        successRate: successRate,
        projectedFutureSessions: projectedFuture,
        failedFacilityNames: failedNames,
        staleFacilityNames: staleNames,
        facilityDiagnostics: diagnostics,
        backendFreshnessScore: status.dataFreshnessScore,
      );
    } on ApiException catch (e, st) {
      appLogger.w('[api-sync] offline or API error', error: e, stackTrace: st);
      final scheduleCountAfter = await _scheduleRepo.countAllSchedules();
      return SyncResult(
        syncStatus: scheduleCountAfter > 0
            ? SyncStatus.partialSuccess
            : SyncStatus.failed,
        updated: 0,
        skipped: 0,
        errors: 1,
        scheduleCountBefore: scheduleCountBefore,
        scheduleCountAfter: scheduleCountAfter,
        rootCauseSummary: 'Backend unavailable — showing cached data',
        isOffline: true,
      );
    }
  }

  Facility _mapFacility(ApiFacilityDto dto) {
    final facilityType = FacilityType.fromStorage(dto.facilityType) ??
        _mapApiFacilityType(dto.type, dto.id, dto.name);
    final dataModel = FacilityDataModel.fromStorage(dto.dataModel) ??
        FacilityDataModel.forType(
          facilityType,
          hasSwimSchedule: dto.hasSwimSchedule,
        );
    final displayStatus = FacilityDisplayStatus.fromStorage(dto.displayStatus) ??
        FacilityDisplayStatus.defaultFor(dataModel);
    final scheduleMode = FacilityScheduleMode.fromStorage(dto.scheduleMode) ??
        FacilityScheduleMode.forDataModel(dataModel);

    final hasVerified = dto.lastVerified != null;
    return Facility(
      id: dto.id,
      name: dto.name,
      address: dto.address,
      latitude: dto.lat,
      longitude: dto.lng,
      region: dto.region,
      url:
          'https://ottawa.ca/en/recreation-and-parks/facilities/place-listing/${dto.id}',
      facilityType: facilityType,
      dataModel: dataModel,
      displayStatus: displayStatus,
      scheduleMode: scheduleMode,
      lastUpdated: dto.lastUpdated,
      lastSuccessfulSyncAt: dto.lastVerified,
      scheduleTrustStatus:
          hasVerified ? ScheduleTrustStatus.verified : ScheduleTrustStatus.cached,
      scheduleSource: hasVerified
          ? ScheduleSource.backendVerified
          : ScheduleSource.fixture,
      scheduleVerifiedAt: dto.lastVerified,
    );
  }

  FacilityType _mapApiFacilityType(String type, String id, String name) {
    switch (type.toLowerCase()) {
      case 'outdoor':
        return FacilityType.outdoorPool;
      case 'wading':
        return FacilityType.wadingPool;
      case 'wave':
        return FacilityType.wavePool;
      case 'indoor':
        return FacilityType.indoorPool;
      case 'splash':
        return FacilityType.splashPad;
      default:
        return FacilityType.inferFromIdAndName(id: id, name: name);
    }
  }

  ScheduleEntry _mapSchedule(String facilityId, ApiScheduleDto row) {
    return ScheduleEntry(
      facilityId: facilityId,
      category: SwimCategories.normalizeStored(row.activityType),
      rawCategory: row.rawCategory ?? row.activityType,
      scheduleType: row.scheduleType ?? 'expanded',
      dayOfWeek: row.dayOfWeek,
      date: row.date,
      startTime: row.startTime,
      endTime: row.endTime,
      dateRangeStart: row.dateRangeStart,
      dateRangeEnd: row.dateRangeEnd,
      lastUpdated: row.lastUpdated,
    );
  }

  ScheduleTrustStatus _trustForSource(String? source, String? sourceStatus) {
    final status = sourceStatus ?? source;
    if (status == 'live' || status == 'backend_verified') {
      return ScheduleTrustStatus.verified;
    }
    if (status == 'fixture') return ScheduleTrustStatus.fixture;
    return ScheduleTrustStatus.cached;
  }

  ScheduleSource _sourceForApi(String? source, String? sourceStatus) {
    final status = sourceStatus ?? source;
    if (status == 'live' || status == 'backend_verified') {
      return ScheduleSource.backendVerified;
    }
    if (status == 'fixture') return ScheduleSource.fixture;
    return ScheduleSource.backendVerified;
  }

  SyncStatus _deriveStatus({
    required int updated,
    required int errors,
    required int total,
    required int scheduleAfter,
  }) {
    if (scheduleAfter == 0 && errors > 0) return SyncStatus.failed;
    if (errors > 0 || (updated == 0 && total > 0)) {
      return SyncStatus.partialSuccess;
    }
    return SyncStatus.success;
  }
}
