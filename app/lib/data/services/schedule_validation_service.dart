import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/ottawa_time.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/schedule_entry.dart';
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
  ScheduleValidationService(this._scheduleRepo, this._facilityRepo);

  final ScheduleRepository _scheduleRepo;
  final FacilityRepository _facilityRepo;

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
    }

    if (warnings.isNotEmpty) {
      appLogger.w('[schedule-validation] ${warnings.length} warning(s)');
    }
    return warnings;
  }
}

class _AuditAccumulator {
  _AuditAccumulator(this.rawName);

  final String rawName;
  int count = 0;
  String normalizedType = 'other';
  final Set<String> facilities = {};
}
