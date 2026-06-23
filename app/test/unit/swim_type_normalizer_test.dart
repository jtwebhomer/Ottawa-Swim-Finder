import 'package:flutter_test/flutter_test.dart';
import 'package:ottawa_swim_finder/data/scraper/parsers/category_normalizer.dart';

void main() {
  group('SwimTypeNormalizer', () {
    test('maps leisure and recreation to general swim', () {
      expect(normalizeSwimCategory('Leisure Swim'), 'general_swim');
      expect(normalizeSwimCategory('Recreation Swim'), 'general_swim');
      expect(normalizeSwimCategory('Public swim'), 'general_swim');
    });

    test('maps Jack Purcell alternate needs swim', () {
      expect(
        normalizeSwimCategory('Alternate needs swim *Reservations required'),
        'general_swim',
      );
    });

    test('maps women before public for combined label', () {
      expect(normalizeSwimCategory("Public swim women's only"), 'womens_swim');
      expect(normalizeSwimCategory("Women's only swim"), 'womens_swim');
    });

    test('maps specialty types', () {
      expect(normalizeSwimCategory('Parent & Tot Swim'), 'parent_tot');
      expect(normalizeSwimCategory('Adult swim'), 'adult_swim');
      expect(normalizeSwimCategory('Aqua therapy'), 'therapeutic_swim');
      expect(normalizeSwimCategory('Aquafit Lite'), 'aquafit');
      expect(normalizeSwimCategory('Lane swim'), 'lane_swim');
    });

    test('generic swim fallback', () {
      expect(normalizeSwimCategory('Rec swim'), 'general_swim');
    });
  });
}
