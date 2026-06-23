import 'dart:convert';
import 'dart:io';

import 'package:ottawa_swim_finder/data/services/fixture_seed_builder.dart';

// ignore_for_file: avoid_print

/// Release gate — fails if fabricated schedules or placeholder generators remain.
void main() {
  var failed = false;

  print('RELEASE GATE AUDIT');
  print('=' * 90);

  // 1. Check generate_schedule_seed.dart for placeholder logic
  final generator = File('tool/generate_schedule_seed.dart').readAsStringSync();
  if (generator.contains('indoorIds') ||
      generator.contains('Bundled seed snapshot — verify on ottawa.ca')) {
    print('FAIL: generate_schedule_seed.dart still references placeholder logic');
    failed = true;
  } else {
    print('PASS: no placeholder generator in generate_schedule_seed.dart');
  }

  // 2. Check bundled seed JSON
  final seedFile = File('assets/schedule_seed.json');
  if (!seedFile.existsSync()) {
    print('FAIL: assets/schedule_seed.json missing');
    exit(1);
  }

  final seed = jsonDecode(seedFile.readAsStringSync()) as Map<String, dynamic>;
  final version = seed['version'] as int? ?? 0;

  if (version < 3) {
    print('FAIL: seed version $version — require v3+');
    failed = true;
  } else {
    print('PASS: seed version $version');
  }

  if (FixtureSeedBuilder.containsPlaceholderNotes(seed)) {
    print('FAIL: schedule_seed.json contains fabricated placeholder sessions');
    failed = true;
  } else {
    print('PASS: no fabricated placeholder notes in seed');
  }

  // 3. Per-facility report
  final canonical =
      jsonDecode(File('assets/facilities_canonical.json').readAsStringSync())
          as Map<String, dynamic>;
  final facilityMeta = (seed['facilities'] as Map<String, dynamic>?) ?? {};
  final byFacility = <String, List<dynamic>>{};
  for (final row in (seed['schedules'] as List)) {
    final id = (row as Map)['facility_id'] as String;
    byFacility.putIfAbsent(id, () => []).add(row);
  }

  print('');
  print(
    '${'Facility'.padRight(42)} ${'Source'.padRight(12)} ${'Sessions'.padLeft(8)} '
    '${'Verified'.padRight(12)} Trust',
  );
  print('-' * 90);

  for (final row in (canonical['facilities'] as List)) {
    final map = row as Map<String, dynamic>;
    final id = map['id'] as String;
    final name = map['name'] as String;
    final sessions = byFacility[id]?.length ?? 0;
    final meta = facilityMeta[id] as Map<String, dynamic>?;
    final source = meta?['schedule_source'] as String? ??
        (sessions > 0 ? 'unknown' : 'none');
    final verified = sessions > 0 && source == 'fixture'
        ? 'fixture'
        : sessions > 0
            ? source
            : '—';
    final trust = sessions == 0
        ? 'UNVERIFIED'
        : source == 'fixture'
            ? 'FIXTURE'
            : 'UNKNOWN';

    if (source == 'unknown' && sessions > 0) {
      print('FAIL: $name has sessions without schedule_source');
      failed = true;
    }

    print(
      '${name.padRight(42)} ${source.padRight(12)} ${sessions.toString().padLeft(8)} '
      '${verified.padRight(12)} $trust',
    );
  }

  print('=' * 90);
  if (failed) {
    print('RELEASE GATE: FAIL');
    exit(1);
  } else {
    print('RELEASE GATE: PASS');
  }
}
