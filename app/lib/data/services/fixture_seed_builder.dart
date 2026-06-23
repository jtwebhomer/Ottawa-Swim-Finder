import 'dart:convert';
import 'dart:io';

import '../../core/utils/ottawa_time.dart';
import '../../data/scraper/parsers/schedule_parser.dart';
import '../../domain/entities/schedule_entry.dart';

/// Builds production seed data exclusively from Ottawa HTML fixtures.
class FixtureSeedBuilder {
  FixtureSeedBuilder({ScheduleParser? parser})
      : _parser = parser ?? ScheduleParser();

  final ScheduleParser _parser;

  static const placeholderMarker = 'Bundled seed snapshot — verify on ottawa.ca';

  /// Maps HTML fixture filenames to Ottawa facility IDs.
  static const fixturePaths = <String, String>{
    'plant-recreation-centre': 'test/fixtures/plant_recreation_centre.html',
    'walter-baker-sports-centre': 'test/fixtures/walter_baker_sports_centre.html',
    'jack-purcell-community-centre':
        'test/fixtures/jack_purcell_community_centre.html',
  };

  /// Optional scraper samples (same parser pipeline).
  static const scraperSamples = <String, String>{
    'jack-purcell-community-centre': '../scraper/jack_purcell_sample.html',
  };

  FixtureSeedBuildResult build({
    DateTime? generatedAt,
    String? workingDirectory,
  }) {
    final cwd = workingDirectory ?? Directory.current.path;
    final now = generatedAt ?? DateTime.now();
    final today = OttawaTime.todayDate();
    final schedules = <Map<String, dynamic>>[];
    final facilityMeta = <String, FixtureFacilityMeta>{};
    final seenFacility = <String>{};

    void ingest(String facilityId, String relativePath) {
      if (seenFacility.contains(facilityId)) return;
      final file = File('$cwd${Platform.pathSeparator}$relativePath');
      if (!file.existsSync()) return;

      final (parsed, _) =
          _parser.parseWithTableInfo(file.readAsStringSync(), facilityId);
      var count = 0;
      for (final row in parsed) {
        if (row.date != null && row.date!.compareTo(today) < 0) continue;
        schedules.add(_rowToJson(row, facilityId));
        count++;
      }

      if (count == 0) return;

      seenFacility.add(facilityId);
      facilityMeta[facilityId] = FixtureFacilityMeta(
        facilityId: facilityId,
        scheduleSource: 'fixture',
        fixturePath: relativePath,
        fixtureGeneratedAtMs: now.millisecondsSinceEpoch,
        sessionCount: count,
      );
    }

    for (final entry in fixturePaths.entries) {
      ingest(entry.key, entry.value);
    }
    for (final entry in scraperSamples.entries) {
      if (seenFacility.contains(entry.key)) continue;
      ingest(entry.key, entry.value);
    }

    return FixtureSeedBuildResult(
      version: 3,
      bundledAtMs: now.millisecondsSinceEpoch,
      fixtureGeneratedAtMs: now.millisecondsSinceEpoch,
      schedules: schedules,
      facilities: facilityMeta,
    );
  }

  Map<String, dynamic> _rowToJson(ScheduleEntry row, String facilityId) {
    return {
      'facility_id': facilityId,
      'category': row.category,
      'raw_category': row.rawCategory,
      'schedule_type': row.scheduleType,
      'schedule_source': 'fixture',
      'day_of_week': row.dayOfWeek,
      'date': row.date,
      'start_time': row.startTime,
      'end_time': row.endTime,
      'notes': row.notes,
      'date_range_start': row.dateRangeStart,
      'date_range_end': row.dateRangeEnd,
    };
  }

  /// Returns true if [payload] contains any fabricated placeholder sessions.
  static bool containsFabricatedData(Map<String, dynamic> payload) {
    for (final row in (payload['schedules'] as List?) ?? const []) {
      final map = row as Map<String, dynamic>;
      final notes = map['notes'] as String? ?? '';
      if (notes.contains(placeholderMarker)) return true;
      if (map['schedule_source'] != 'fixture' &&
          map['schedule_source'] != 'live') {
        return false;
      }
    }
    return false;
  }

  static bool containsPlaceholderNotes(Map<String, dynamic> payload) {
    for (final row in (payload['schedules'] as List?) ?? const []) {
      final notes = (row as Map<String, dynamic>)['notes'] as String? ?? '';
      if (notes.contains(placeholderMarker)) return true;
    }
    return false;
  }
}

class FixtureSeedBuildResult {
  const FixtureSeedBuildResult({
    required this.version,
    required this.bundledAtMs,
    required this.fixtureGeneratedAtMs,
    required this.schedules,
    required this.facilities,
  });

  final int version;
  final int bundledAtMs;
  final int fixtureGeneratedAtMs;
  final List<Map<String, dynamic>> schedules;
  final Map<String, FixtureFacilityMeta> facilities;

  Map<String, dynamic> toJson() => {
        'version': version,
        'bundled_at_ms': bundledAtMs,
        'fixture_generated_at_ms': fixtureGeneratedAtMs,
        'facilities': {
          for (final e in facilities.entries) e.key: e.value.toJson(),
        },
        'schedules': schedules,
      };
}

class FixtureFacilityMeta {
  const FixtureFacilityMeta({
    required this.facilityId,
    required this.scheduleSource,
    required this.fixturePath,
    required this.fixtureGeneratedAtMs,
    required this.sessionCount,
  });

  final String facilityId;
  final String scheduleSource;
  final String fixturePath;
  final int fixtureGeneratedAtMs;
  final int sessionCount;

  Map<String, dynamic> toJson() => {
        'facility_id': facilityId,
        'schedule_source': scheduleSource,
        'fixture_path': fixturePath,
        'fixture_generated_at_ms': fixtureGeneratedAtMs,
        'session_count': sessionCount,
      };

  factory FixtureFacilityMeta.fromJson(Map<String, dynamic> json) {
    return FixtureFacilityMeta(
      facilityId: json['facility_id'] as String,
      scheduleSource: json['schedule_source'] as String? ?? 'fixture',
      fixturePath: json['fixture_path'] as String? ?? '',
      fixtureGeneratedAtMs: json['fixture_generated_at_ms'] as int? ?? 0,
      sessionCount: json['session_count'] as int? ?? 0,
    );
  }
}
