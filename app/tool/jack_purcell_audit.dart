// ignore_for_file: avoid_print

import 'dart:io';

import 'package:ottawa_swim_finder/core/constants/app_constants.dart';
import 'package:ottawa_swim_finder/data/scraper/parsers/category_normalizer.dart';
import 'package:ottawa_swim_finder/data/scraper/parsers/schedule_parser.dart';

const _jackPurcellRows = [
  'Alternate needs swim',
  'Lane swim',
  'Aqua therapy',
  'Chronic pain',
  'Aquafit Lite',
  'Public swim',
  "Women's only swim",
  "Public swim women's only",
];

void main() {
  final samplePath = r'C:\Users\Jtcra\ottawa_swim_finder\scraper\jack_purcell_sample.html';
  if (!File(samplePath).existsSync()) {
    print('Sample HTML not found at $samplePath');
    exit(1);
  }

  final html = File(samplePath).readAsStringSync();
  final parser = ScheduleParser();
  final entries = parser.parse(html, 'jack-purcell-community-centre');

  print('JACK PURCELL PIPELINE AUDIT');
  print('=' * 72);

  for (final expected in _jackPurcellRows) {
    final isRow = isSwimRow(expected);
    final normalized = SwimTypeNormalizer.normalize(expected);
    final parsedCount =
        entries.where((e) => _matchesRaw(e.rawCategory, expected)).length;

    print('');
    print('RAW: $expected');
    print('  isSwimRow (parser gate): ${isRow ? 'PASS' : 'DROP'}');
    print('  normalized_category: $normalized');
    print('  parsed_entries: $parsedCount');
    print('  stored_in_db (if synced): ${parsedCount > 0 ? 'YES' : 'NO'}');
    print('  visible_in_ui (if in DB): ${parsedCount > 0 ? 'YES' : 'NO'}');
  }

  print('\n${'=' * 72}');
  print('All unique parsed raw categories (${entries.map((e) => e.rawCategory).toSet().length}):');
  final grouped = <String, String>{};
  for (final e in entries) {
    final raw = e.rawCategory ?? '';
    grouped[raw] = e.category;
  }
  for (final raw in grouped.keys.toList()..sort()) {
    print('  $raw -> ${grouped[raw]} (${entries.where((e) => e.rawCategory == raw).length})');
  }
  print('\nTotal parsed schedule entries: ${entries.length}');
}

bool _matchesRaw(String? actual, String expected) {
  if (actual == null) return false;
  final a = actual.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  final e = expected.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  return a.contains(e) || e.contains(a);
}
