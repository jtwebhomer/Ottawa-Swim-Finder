import 'facility_inclusion_audit_service.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/ottawa_time.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/facility_inclusion_trace.dart';
import '../../domain/repositories/repositories.dart';
import '../../data/scraper/parsers/category_normalizer.dart';

class RawNameAuditEntry {
  const RawNameAuditEntry({
    required this.rawName,
    required this.count,
    required this.normalizedType,
    required this.facilities,
  });

  final String rawName;
  final int count;
  final String normalizedType;
  final List<String> facilities;
}

class ScheduleValidationWarning {
  const ScheduleValidationWarning({
    required this.code,
    required this.message,
    this.facilityId,
  });

  final String code;
  final String message;
  final String? facilityId;
}

/// Audits stored schedules and detects display mismatches.
class ScheduleValidationService {
  ScheduleValidationService(
    this._scheduleRepo,
    this._facilityRepo, {
    FacilityInclusionAuditService? inclusionAuditService,
  }) : _inclusionAudit = inclusionAuditService;

  final ScheduleRepository _scheduleRepo;
  final FacilityRepository _facilityRepo;
  final FacilityInclusionAuditService? _inclusionAudit;

  Future<List<RawNameAuditEntry>> auditRawNames() async {
    final today = OttawaTime.todayDate();
    final facilities = await _facilityRepo.getAllFacilities();
    final map = <String, _AuditAccumulator>{};

    for (final facility in facilities) {
      final schedules =
          await _scheduleRepo.getSchedulesForFacility(facility.id, date: today);
      for (final entry in schedules) {
        final raw = entry.rawCategory ?? entry.category;
        final acc = map.putIfAbsent(raw, () => _AuditAccumulator(raw));
        acc.count++;
        acc.normalizedType = entry.category;
        acc.facilities.add(facility.name);
      }
    }

    return map.values
        .map(
          (a) => RawNameAuditEntry(
            rawName: a.rawName,
            count: a.count,
            normalizedType: a.normalizedType,
            facilities: a.facilities.toList()..sort(),
          ),
        )
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  Future<List<ScheduleValidationWarning>> runValidationChecks() async {
    final warnings = <ScheduleValidationWarning>[];
    final today = OttawaTime.todayDate();
    final now = OttawaTime.nowTime();
    final facilities = await _facilityRepo.getAllFacilities();

    for (final facility in facilities) {
      final allToday =
          await _scheduleRepo.getSchedulesForFacility(facility.id, date: today);
      final displayable = allToday
          .where((e) => SwimTypeNormalizer.isDisplayable(e.category))
          .toList();
      final timeline =
          await _scheduleRepo.getTimelineForDate(today, facilityId: facility.id);

      if (allToday.isNotEmpty && displayable.isEmpty) {
        warnings.add(ScheduleValidationWarning(
          code: 'all_excluded',
          facilityId: facility.id,
          message:
              '${facility.name}: ${allToday.length} sessions today but none are displayable types',
        ));
      }

      if (allToday.length > timeline.length && timeline.isEmpty) {
        warnings.add(ScheduleValidationWarning(
          code: 'timeline_empty',
          facilityId: facility.id,
          message:
              '${facility.name}: ${allToday.length} in DB but Today query returned 0',
        ));
      }

      final remaining = allToday
          .where((e) => OttawaTime.isRemainingToday(end: e.endTime, time: now))
          .toList();
      final remainingDisplayable = remaining
          .where((e) => SwimTypeNormalizer.isDisplayable(e.category))
          .toList();

      if (remaining.isNotEmpty && remainingDisplayable.isEmpty) {
        warnings.add(ScheduleValidationWarning(
          code: 'remaining_hidden',
          facilityId: facility.id,
          message:
              '${facility.name}: ${remaining.length} remaining sessions hidden by category filter',
        ));
      }

      for (final entry in allToday) {
        if (entry.dateRangeStart != null &&
            entry.dateRangeEnd != null &&
            entry.date != null &&
            (entry.date!.compareTo(entry.dateRangeStart!) < 0 ||
                entry.date!.compareTo(entry.dateRangeEnd!) > 0)) {
          warnings.add(ScheduleValidationWarning(
            code: 'outside_season',
            facilityId: facility.id,
            message:
                '${facility.name}: ${entry.date} outside season ${entry.dateRangeStart}–${entry.dateRangeEnd}',
          ));
          break;
        }
      }

      for (final entry in allToday) {
        if (entry.date == null || entry.date!.isEmpty) {
          warnings.add(ScheduleValidationWarning(
            code: 'missing_date',
            facilityId: facility.id,
            message: '${facility.name}: session missing date (${entry.rawCategory})',
          ));
        }
        if (entry.startTime.isEmpty || entry.endTime.isEmpty) {
          warnings.add(ScheduleValidationWarning(
            code: 'missing_time',
            facilityId: facility.id,
            message: '${facility.name}: session missing start/end time',
          ));
        }
        if (entry.startTime.compareTo(entry.endTime) >= 0) {
          warnings.add(ScheduleValidationWarning(
            code: 'invalid_time',
            facilityId: facility.id,
            message:
                '${facility.name}: invalid ${entry.startTime}-${entry.endTime} (${entry.rawCategory})',
          ));
        }
        if (entry.rawCategory != null &&
            SwimTypeNormalizer.normalize(entry.rawCategory!) == 'other' &&
            entry.rawCategory!.toLowerCase().contains('swim')) {
          warnings.add(ScheduleValidationWarning(
            code: 'unknown_type',
            facilityId: facility.id,
            message:
                'Unknown swim type "${entry.rawCategory}" at ${facility.name}',
          ));
        }
      }

      final futureForFacility = await _scheduleRepo.countFutureSessionsForFacility(
        facility.id,
        today,
      );
      if (futureForFacility > 100) {
        final next14 = await _countSessionsInRange(
          facility.id,
          today,
          OttawaTime.formatDate(DateTime.now().add(const Duration(days: 13))),
        );
        if (next14 == 0) {
          warnings.add(ScheduleValidationWarning(
            code: 'future_gap',
            facilityId: facility.id,
            message:
                '${facility.name}: $futureForFacility future sessions but none in next 14 days',
          ));
        }
      }

      if (allToday.isEmpty && futureForFacility == 0) {
        final total = await _scheduleRepo.countSchedulesForFacility(facility.id);
        if (total > 0) {
          warnings.add(ScheduleValidationWarning(
            code: 'no_future_swims',
            facilityId: facility.id,
            message:
                '${facility.name}: $total stored sessions but none today or future',
          ));
        }
      }

      if (allToday.isEmpty) {
        final anyFuture = await _scheduleRepo.countSchedulesForFacility(facility.id);
        if (anyFuture > 0) {
          warnings.add(ScheduleValidationWarning(
            code: 'no_today_rows',
            facilityId: facility.id,
            message:
                '${facility.name}: no sessions dated $today but $anyFuture total rows stored',
          ));
        }
      }

      final tomorrow = OttawaTime.formatDate(
        DateTime.now().add(const Duration(days: 1)),
      );
      final tomorrowCount = (await _scheduleRepo.getTimelineForDate(
        tomorrow,
        facilityId: facility.id,
      ))
          .length;
      final storedFuture = await _scheduleRepo.searchSchedules(
        facilityId: facility.id,
        date: tomorrow,
      );
      if (storedFuture.isNotEmpty && tomorrowCount == 0) {
        warnings.add(ScheduleValidationWarning(
          code: 'future_hidden',
          facilityId: facility.id,
          message:
              '${facility.name}: ${storedFuture.length} sessions on $tomorrow not returned by timeline query',
        ));
      }
    }

    final todayStr = OttawaTime.todayDate();
    final futureTotal = await _scheduleRepo.countFutureSessions(todayStr);
    if (futureTotal == 0) {
      final all = await _scheduleRepo.countAllSchedules();
      if (all > 50) {
        warnings.add(const ScheduleValidationWarning(
          code: 'no_future_sessions',
          message:
              'Database has sessions but none dated after today — check parser expansion',
        ));
      }
      if (all > 0 && all < 100) {
        warnings.add(ScheduleValidationWarning(
          code: 'low_session_count',
          message: 'Suspiciously low session count: $all total rows',
        ));
      }
    }

    if (warnings.isNotEmpty) {
      appLogger.w('[schedule-validation] ${warnings.length} warning(s)');
    }
    return warnings;
  }

  Future<int> _countSessionsInRange(
    String facilityId,
    String fromDate,
    String toDate,
  ) async {
    var total = 0;
    var current = DateTime.parse(fromDate);
    final end = DateTime.parse(toDate);
    while (!current.isAfter(end)) {
      final d = OttawaTime.formatDate(current);
      final rows = await _scheduleRepo.searchSchedules(
        facilityId: facilityId,
        date: d,
      );
      total += rows.length;
      current = current.add(const Duration(days: 1));
    }
    return total;
  }

  Future<FacilityCatalogAudit> runFacilityInclusionAudit({
    List<Facility>? uiFacilities,
  }) async {
    final audit = _inclusionAudit;
    if (audit == null) {
      throw StateError('FacilityInclusionAuditService not configured');
    }
    return audit.runAudit(uiFacilities: uiFacilities);
  }
}

class _AuditAccumulator {
  _AuditAccumulator(this.rawName);

  final String rawName;
  int count = 0;
  String normalizedType = 'other';
  final Set<String> facilities = {};
}
