import 'dart:convert';
import 'dart:io';

import 'package:ottawa_swim_finder/core/constants/app_constants.dart';
import 'package:ottawa_swim_finder/data/scraper/parsers/category_normalizer.dart';
import 'package:ottawa_swim_finder/data/scraper/parsers/schedule_parser.dart';
import 'package:ottawa_swim_finder/domain/entities/facility_type.dart';

// ignore_for_file: avoid_print

/// System-wide category + facility coverage audit (fixtures + seed + canonical).
Future<void> main() async {
  final parser = ScheduleParser();

  print('OTTAWA SWIM FINDER — SYSTEM COVERAGE AUDIT');
  print('=' * 80);

  // --- PART 1: Category audit from HTML fixtures ---
  final fixtureDir = Directory('test/fixtures');
  final scraperDir = Directory('../scraper');
  final htmlFiles = <File>[
    ...fixtureDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.html')),
    if (scraperDir.existsSync())
      ...scraperDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.html')),
  ];

  final categoryAgg = <String, _CategoryAgg>{};
  for (final file in htmlFiles) {
    final facilityId = _facilityIdFromPath(file.path);
    final entries = parser.parse(file.readAsStringSync(), facilityId);
    for (final e in entries) {
      final raw = SwimTypeNormalizer.cleanRawActivityLabel(e.rawCategory ?? '');
      final norm = e.category;
      final key = '$raw|$norm';
      categoryAgg.putIfAbsent(key, () => _CategoryAgg(raw, norm)).add(facilityId);
    }
  }

  // --- Seed JSON categories ---
  final seedFile = File('assets/schedule_seed.json');
  if (seedFile.existsSync()) {
    final seed = jsonDecode(seedFile.readAsStringSync()) as Map<String, dynamic>;
    for (final row in (seed['schedules'] as List).cast<Map<String, dynamic>>()) {
      final raw = row['raw_category'] as String? ?? row['category'] as String;
      final norm = row['category'] as String;
      final fid = row['facility_id'] as String;
      final key = '$raw|$norm';
      categoryAgg.putIfAbsent(key, () => _CategoryAgg(raw, norm)).add(fid);
    }
  }

  print('\nPART 1 — CATEGORY INVENTORY');
  print('${'Raw Category'.padRight(36)} ${'Normalized'.padRight(20)} Facilities Sessions');
  print('-' * 80);

  final sorted = categoryAgg.values.toList()
    ..sort((a, b) => b.sessionEstimate.compareTo(a.sessionEstimate));

  for (final row in sorted) {
    print(
      '${row.raw.padRight(36)} ${row.normalized.padRight(20)} '
      '${row.facilities.length.toString().padLeft(10)} '
      '${row.sessionEstimate.toString().padLeft(10)}',
    );
  }

  // Merge analysis
  print('\nMERGE GROUPS (multiple raw → same normalized):');
  final byNorm = <String, List<String>>{};
  for (final row in categoryAgg.values) {
    byNorm.putIfAbsent(row.normalized, () => []).add(row.raw);
  }
  for (final entry in byNorm.entries) {
    final raws = entry.value.toSet().toList()..sort();
    if (raws.length > 1) {
      print('  ${entry.key}: ${raws.join(' | ')}');
    }
  }

  // --- PART 2: Facility discovery audit ---
  print('\n${'=' * 80}');
  print('PART 2 — FACILITY DISCOVERY');
  final canonicalFile = File('assets/facilities_canonical.json');
  final canonicalData =
      jsonDecode(canonicalFile.readAsStringSync()) as Map<String, dynamic>;
  final canonical = (canonicalData['facilities'] as List).cast<Map<String, dynamic>>();
  print(
    '${'Facility Name'.padRight(40)} ${'Type'.padRight(16)} Discovered Mapped Visible',
  );
  print('-' * 80);

  for (final row in canonical) {
    final name = row['name'] as String;
    final id = row['id'] as String;
    final type = FacilityType.inferFromIdAndName(
      id: id,
      name: name,
      explicit: row['facility_type'] as String?,
    );
    final scheduleMode = row['schedule_mode'] as String?;
    final hasSwimSchedule = scheduleMode == 'HAS_SWIM_SCHEDULE';
    final lat = row['latitude'];
    final lng = row['longitude'];
    final mapped = lat != null && lng != null;
    final visible = mapped;
    print(
      '${name.padRight(40)} ${type.label.padRight(16)} '
      '${hasSwimSchedule || type == FacilityType.outdoorPool || type == FacilityType.wadingPool ? 'Y' : 'N'.padLeft(11)} '
      '${mapped ? 'Y' : 'N'.padLeft(6)} '
      '${visible ? 'Y' : 'N'.padLeft(7)}',
    );
  }

  final byType = <FacilityType, int>{};
  for (final t in FacilityType.values) {
    byType[t] = canonical
        .where(
          (row) =>
              FacilityType.inferFromIdAndName(
                id: row['id'] as String,
                name: row['name'] as String,
                explicit: row['facility_type'] as String?,
              ) ==
              t,
        )
        .length;
  }

  print('\nFACILITY COUNTS BY TYPE:');
  for (final t in FacilityType.values) {
    print('  ${t.label}: ${byType[t]}');
  }
  print('  Total aquatic: ${canonical.length}');

  // --- PART 3: Loss points summary ---
  print('\n${'=' * 80}');
  print('PART 3 — ARCHITECTURAL LOSS POINTS');
  print('  1. Parser isSwimRow gate — drops rows normalizing to other without aquatic keywords');
  print('  2. Normalization merges distinct Ottawa labels into shared buckets (raw preserved in DB)');
  print('  3. Seed placeholders — 17 facilities get only Lane/Leisure/Family unless HTML fixture exists');
  print('  4. Outdoor/wading — seasonal/open-hours; no swim table sync (pins show Seasonal/Open)');
  print('  5. UI filters — now dynamic from DB inventory (raw + normalized)');
}

String _facilityIdFromPath(String path) {
  final base = path.split(Platform.pathSeparator).last.replaceAll('.html', '');
  if (base.contains('jack_purcell')) return 'jack-purcell-community-centre';
  if (base.contains('plant')) return 'plant-recreation-centre';
  if (base.contains('walter_baker')) return 'walter-baker-sports-centre';
  return base.replaceAll('_', '-');
}

class _CategoryAgg {
  _CategoryAgg(this.raw, this.normalized);

  final String raw;
  final String normalized;
  final Set<String> facilities = {};
  int sessionEstimate = 0;

  void add(String facilityId) {
    facilities.add(facilityId);
    sessionEstimate++;
  }
}
