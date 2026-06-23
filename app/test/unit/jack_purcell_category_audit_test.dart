import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ottawa_swim_finder/core/constants/app_constants.dart';
import 'package:ottawa_swim_finder/data/scraper/parsers/category_normalizer.dart';
import 'package:ottawa_swim_finder/data/scraper/parsers/schedule_parser.dart';

/// End-to-end category trace for Jack Purcell Community Centre.
void main() {
  const facilityId = 'jack-purcell-community-centre';

  const expectedRows = <({String raw, String normalized})>[
    (raw: 'Alternate needs swim', normalized: SwimCategories.generalSwim),
    (raw: 'Lane swim', normalized: SwimCategories.laneSwim),
    (raw: 'Aqua therapy', normalized: SwimCategories.therapeuticSwim),
    (raw: 'Chronic pain', normalized: SwimCategories.therapeuticSwim),
    (raw: 'Aquafit Lite', normalized: SwimCategories.aquafit),
    (raw: 'Public swim', normalized: SwimCategories.generalSwim),
    (raw: "Women's only swim", normalized: SwimCategories.womensSwim),
    (raw: "Public swim women's only", normalized: SwimCategories.womensSwim),
  ];

  late List<dynamic> parsed;
  late File sample;

  setUpAll(() {
    sample = File('test/fixtures/jack_purcell_community_centre.html');
    if (!sample.existsSync()) {
      sample = File(
        r'C:\Users\Jtcra\ottawa_swim_finder\scraper\jack_purcell_sample.html',
      );
    }
    final parser = ScheduleParser();
    parsed = parser.parse(sample.readAsStringSync(), facilityId);
  });

  for (final row in expectedRows) {
    test('${row.raw} passes parser gate and normalizes to ${row.normalized}', () {
      expect(sample.existsSync(), isTrue, reason: 'Jack Purcell HTML fixture missing');

      expect(
        isSwimRow(row.raw),
        isTrue,
        reason: 'isSwimRow() must not drop "${row.raw}"',
      );
      expect(
        SwimTypeNormalizer.normalize(row.raw),
        row.normalized,
      );

      final matches = parsed.where(
        (e) => _rawMatches(e.rawCategory as String?, row.raw),
      );
      expect(
        matches,
        isNotEmpty,
        reason: 'Parser must emit sessions for "${row.raw}"',
      );
      for (final entry in matches) {
        expect(entry.category, row.normalized);
        expect(
          SwimTypeNormalizer.cleanRawActivityLabel(entry.rawCategory ?? ''),
          row.raw,
        );
      }
    });
  }

  test('raw labels are preserved distinctly (no merge into one label)', () {
    final rawLabels = parsed
        .map((e) => SwimTypeNormalizer.cleanRawActivityLabel(e.rawCategory ?? ''))
        .toSet();
    for (final row in expectedRows) {
      expect(rawLabels, contains(row.raw));
    }
  });

  test('multiple general_swim rows keep separate raw names', () {
    final generalRaws = parsed
        .where((e) => e.category == SwimCategories.generalSwim)
        .map((e) => SwimTypeNormalizer.cleanRawActivityLabel(e.rawCategory ?? ''))
        .toSet();
    expect(generalRaws, contains('Alternate needs swim'));
    expect(generalRaws, contains('Public swim'));
  });
}

bool _rawMatches(String? actual, String expected) {
  if (actual == null) return false;
  final cleaned = SwimTypeNormalizer.cleanRawActivityLabel(actual).toLowerCase();
  return cleaned == expected.toLowerCase();
}
