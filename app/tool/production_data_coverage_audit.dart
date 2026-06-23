// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

void main() {
  final canonical =
      jsonDecode(File('assets/facilities_canonical.json').readAsStringSync())
          as Map<String, dynamic>;
  final seed =
      jsonDecode(File('assets/schedule_seed.json').readAsStringSync())
          as Map<String, dynamic>;

  final bundledAtMs = seed['bundled_at_ms'] as int?;
  final bundledAt = bundledAtMs != null
      ? DateTime.fromMillisecondsSinceEpoch(bundledAtMs)
      : null;

  const fixtureIds = {
    'plant-recreation-centre',
    'walter-baker-sports-centre',
    'jack-purcell-community-centre',
  };

  const placeholderNote = 'Bundled seed snapshot — verify on ottawa.ca';

  final byFacility = <String, List<Map<String, dynamic>>>{};
  for (final row in (seed['schedules'] as List).cast<Map<String, dynamic>>()) {
    final id = row['facility_id'] as String;
    byFacility.putIfAbsent(id, () => []).add(row);
  }

  final today = DateTime.now();
  final todayStr =
      '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

  print('PRODUCTION DATA COVERAGE AUDIT');
  print('Bundled seed version: ${seed['version']}');
  print('Bundled at: $bundledAt');
  print('Report generated: ${DateTime.now().toIso8601String()}');
  print('=' * 110);
  print(
    '${'Facility'.padRight(42)} ${'Type'.padRight(14)} ${'Source'.padRight(22)} '
    '${'Sessions'.padLeft(8)} ${'Next Swim'.padRight(12)} Last Verified',
  );
  print('-' * 110);

  var placeholderCount = 0;
  var fixtureCount = 0;
  var noDataCount = 0;
  var outdoorNoData = 0;

  for (final row in (canonical['facilities'] as List).cast<Map<String, dynamic>>()) {
    final id = row['id'] as String;
    final name = row['name'] as String;
    final type = row['facility_type'] as String;
    final scheduleMode = row['schedule_mode'] as String;
    final rows = byFacility[id] ?? [];

    String source;
    if (rows.isEmpty) {
      source = 'No Schedule Data';
      noDataCount++;
      if (type == 'OUTDOOR_POOL' || type == 'WADING_POOL') outdoorNoData++;
    } else if (fixtureIds.contains(id)) {
      source = 'HTML Fixture';
      fixtureCount++;
    } else if (rows.every(
      (r) => (r['notes'] as String?)?.contains(placeholderNote) ?? false,
    )) {
      source = 'Seeded Placeholder';
      placeholderCount++;
    } else {
      source = 'Mixed/Unknown';
    }

    String? nextDate;
    for (final r in rows) {
      final d = r['date'] as String?;
      if (d == null || d.compareTo(todayStr) < 0) continue;
      if (nextDate == null || d.compareTo(nextDate) < 0) nextDate = d;
    }

    final verified = bundledAt?.toIso8601String().split('T').first ?? '—';

    print(
      '${name.padRight(42)} ${type.padRight(14)} ${source.padRight(22)} '
      '${rows.length.toString().padLeft(8)} ${(nextDate ?? '—').padRight(12)} $verified',
    );
  }

  print('=' * 110);
  print('SUMMARY');
  print('  HTML Fixture facilities:     $fixtureCount');
  print('  Seeded Placeholder:          $placeholderCount');
  print('  No Schedule Data:            $noDataCount (outdoor/wading: $outdoorNoData)');
  print('  Total facilities:            ${(canonical['facilities'] as List).length}');
  print('  Total seed sessions:         ${(seed['schedules'] as List).length}');
  print('');
  print('LIVE OTTAWA DATA IN BUNDLE: 0 facilities (live sync is runtime-only)');
  print('BOT PROTECTION: Ottawa.ca blocks automated fetches in CI/integration tests');
}
