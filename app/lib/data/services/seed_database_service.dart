import 'dart:convert';

import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/entities/sync_status.dart';
import '../../domain/repositories/repositories.dart';
import 'facility_discovery_service.dart';

/// Loads bundled facility + schedule seed data on first launch.
class SeedDatabaseService {
  SeedDatabaseService({
    required FacilityRepository facilityRepo,
    required ScheduleRepository scheduleRepo,
    required SettingsRepository settingsRepo,
    FacilityDiscoveryService? discoveryService,
  })  : _facilityRepo = facilityRepo,
        _scheduleRepo = scheduleRepo,
        _settingsRepo = settingsRepo,
        _discovery = discoveryService ?? FacilityDiscoveryService();

  static const seedAssetPath = 'assets/schedule_seed.json';
  static const seedVersionKey = 'seed_version';
  static const seedLoadedAtKey = 'seed_loaded_at';
  static const seedBundledAtKey = 'seed_bundled_at';

  final FacilityRepository _facilityRepo;
  final ScheduleRepository _scheduleRepo;
  final SettingsRepository _settingsRepo;
  final FacilityDiscoveryService _discovery;

  Future<SeedLoadResult> ensureSeeded({bool force = false}) async {
    final existingFacilities = await _facilityRepo.getAllFacilities();
    final scheduleCount = await _scheduleRepo.countAllSchedules();
    final seedLoaded = await _settingsRepo.getString(seedLoadedAtKey);

    if (!force &&
        seedLoaded != null &&
        existingFacilities.isNotEmpty &&
        scheduleCount > 0) {
      return SeedLoadResult(
        loaded: false,
        facilityCount: existingFacilities.length,
        scheduleCount: scheduleCount,
        bundledAt: await _readBundledAt(),
      );
    }

    final canonical = await _discovery.loadCanonicalFacilities();
    final seedPayload = await _loadSeedPayload();
    final bundledAt = seedPayload?.bundledAtMs;
    final now = DateTime.now().millisecondsSinceEpoch;

    var facilitiesLoaded = 0;
    for (final facility in canonical) {
      final hasSeedSchedules = seedPayload?.scheduleCountFor(facility.id) ?? 0;
      final seededFacility = facility.copyWith(
        lastSuccessfulSyncAt: hasSeedSchedules > 0 ? bundledAt ?? now : null,
        syncStatus: hasSeedSchedules > 0
            ? FacilitySyncStatus.stale
            : FacilitySyncStatus.failed,
        lastUpdated: bundledAt ?? now,
      );
      await _facilityRepo.upsertFacility(seededFacility);
      facilitiesLoaded++;
    }

    var schedulesLoaded = 0;
    if (seedPayload != null) {
      for (final group in seedPayload.schedulesByFacility.entries) {
        await _scheduleRepo.replaceSchedulesForFacility(group.key, group.value);
        schedulesLoaded += group.value.length;
      }
    }

    await _settingsRepo.setString(seedLoadedAtKey, now.toString());
    if (bundledAt != null) {
      await _settingsRepo.setString(seedBundledAtKey, bundledAt.toString());
    }
    await _settingsRepo.setString(
      seedVersionKey,
      seedPayload?.version.toString() ?? '1',
    );

    appLogger.i(
      '[seed] Loaded $facilitiesLoaded facilities and $schedulesLoaded schedules',
    );

    return SeedLoadResult(
      loaded: true,
      facilityCount: facilitiesLoaded,
      scheduleCount: schedulesLoaded,
      bundledAt: bundledAt != null
          ? DateTime.fromMillisecondsSinceEpoch(bundledAt)
          : null,
    );
  }

  Future<DateTime?> _readBundledAt() async {
    final raw = await _settingsRepo.getString(seedBundledAtKey);
    final ms = int.tryParse(raw ?? '');
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<_SeedPayload?> _loadSeedPayload() async {
    try {
      final jsonStr = await rootBundle.loadString(seedAssetPath);
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      return _SeedPayload.fromJson(data);
    } catch (e, st) {
      appLogger.w('[seed] No schedule seed asset', error: e, stackTrace: st);
      return null;
    }
  }
}

class SeedLoadResult {
  const SeedLoadResult({
    required this.loaded,
    required this.facilityCount,
    required this.scheduleCount,
    this.bundledAt,
  });

  final bool loaded;
  final int facilityCount;
  final int scheduleCount;
  final DateTime? bundledAt;
}

class _SeedPayload {
  _SeedPayload({
    required this.version,
    required this.bundledAtMs,
    required this.schedulesByFacility,
  });

  final int version;
  final int? bundledAtMs;
  final Map<String, List<ScheduleEntry>> schedulesByFacility;

  int scheduleCountFor(String facilityId) =>
      schedulesByFacility[facilityId]?.length ?? 0;

  factory _SeedPayload.fromJson(Map<String, dynamic> json) {
    final bundledAtRaw = json['bundled_at_ms'] as int?;
    final schedules = <String, List<ScheduleEntry>>{};
    final rows = (json['schedules'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];

    for (final row in rows) {
      final facilityId = row['facility_id'] as String;
      schedules
          .putIfAbsent(facilityId, () => [])
          .add(
            ScheduleEntry(
              facilityId: facilityId,
              category: row['category'] as String,
              rawCategory: row['raw_category'] as String?,
              scheduleType: row['schedule_type'] as String? ?? 'expanded',
              dayOfWeek: row['day_of_week'] as int?,
              date: row['date'] as String?,
              startTime: row['start_time'] as String,
              endTime: row['end_time'] as String,
              notes: row['notes'] as String?,
              dateRangeStart: row['date_range_start'] as String?,
              dateRangeEnd: row['date_range_end'] as String?,
              lastUpdated: bundledAtRaw,
            ),
          );
    }

    return _SeedPayload(
      version: json['version'] as int? ?? 1,
      bundledAtMs: bundledAtRaw,
      schedulesByFacility: schedules,
    );
  }
}
