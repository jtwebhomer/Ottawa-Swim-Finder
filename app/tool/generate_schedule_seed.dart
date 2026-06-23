// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:ottawa_swim_finder/data/services/fixture_seed_builder.dart';

/// Generates production seed v3 from Ottawa HTML fixtures only.
Future<void> main() async {
  final builder = FixtureSeedBuilder();
  final result = builder.build();
  final payload = result.toJson();

  if (FixtureSeedBuilder.containsPlaceholderNotes(payload)) {
    stderr.writeln('ERROR: fabricated placeholder notes detected — aborting');
    exit(1);
  }

  final out = File('assets/schedule_seed.json');
  await out.writeAsString(const JsonEncoder.withIndent('  ').convert(payload));

  print('Wrote seed v${result.version}: ${result.schedules.length} sessions');
  print('Fixture facilities: ${result.facilities.length}');
  for (final meta in result.facilities.values) {
    print('  ${meta.facilityId}: ${meta.sessionCount} sessions');
  }
}
