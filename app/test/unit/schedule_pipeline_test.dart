import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ottawa_swim_finder/core/utils/ottawa_time.dart';
import 'package:ottawa_swim_finder/data/scraper/parsers/schedule_parser.dart';

void main() {
  group('OttawaTime', () {
    test('parses standard am/pm ranges', () {
      final ranges = OttawaTime.extractTimeRanges('8 - 9 am');
      expect(ranges, [('08:00', '09:00', null)]);
    });

    test('parses noon-crossing range 11 - 1 pm as morning', () {
      final ranges = OttawaTime.extractTimeRanges('11 - 1 pm');
      expect(ranges.single.$1, '11:00');
      expect(ranges.single.$2, '13:00');
    });

    test('parses 10 am - 1 pm', () {
      final ranges = OttawaTime.extractTimeRanges('10 am - 1 pm');
      expect(ranges.single.$1, '10:00');
      expect(ranges.single.$2, '13:00');
    });

    test('parses evening range 5 - 6 pm', () {
      final ranges = OttawaTime.extractTimeRanges('5 - 6 pm');
      expect(ranges.single.$1, '17:00');
      expect(ranges.single.$2, '18:00');
    });

    test('parses "to" separator', () {
      final ranges = OttawaTime.extractTimeRanges('6 to 9 pm');
      expect(ranges.single.$1, '18:00');
      expect(ranges.single.$2, '21:00');
    });

    test('rejects invalid range where start >= end', () {
      expect(OttawaTime.parseRange('1 pm', '11 am'), isNull);
    });

    test('parses noon keyword', () {
      final ranges = OttawaTime.extractTimeRanges('Noon - 1 pm');
      expect(ranges.single.$1, '12:00');
      expect(ranges.single.$2, '13:00');
    });

    test('isActiveAt uses inclusive start exclusive end', () {
      expect(
        OttawaTime.isActiveAt(start: '17:00', end: '18:00', time: '17:00'),
        isTrue,
      );
      expect(
        OttawaTime.isActiveAt(start: '17:00', end: '18:00', time: '18:00'),
        isFalse,
      );
    });
  });

  group('ScheduleParser date range', () {
    test('parses Jack Purcell season caption April 27 to June 28', () {
      final parser = ScheduleParser();
      final sample = File(
        r'C:\Users\Jtcra\ottawa_swim_finder\scraper\jack_purcell_sample.html',
      );
      if (!sample.existsSync()) return;

      final entries = parser.parse(
        sample.readAsStringSync(),
        'jack-purcell-community-centre',
      );
      expect(entries, isNotEmpty);

      final futureDates = entries
          .where((e) => e.date != null && e.date!.compareTo(OttawaTime.todayDate()) > 0)
          .toList();
      expect(
        futureDates,
        isNotEmpty,
        reason: 'Season expansion should produce future dated sessions',
      );
    });
  });

  group('Jack Purcell live HTML', () {
    test('parses evening swims when HTML sample exists', () {
      final sample = File(
        r'C:\Users\Jtcra\ottawa_swim_finder\scraper\jack_purcell_sample.html',
      );
      if (!sample.existsSync()) {
        // Skip when sample not checked in; run scraper fetch locally to generate.
        return;
      }

      final parser = ScheduleParser();
      final entries = parser.parse(sample.readAsStringSync(), 'jack-purcell-community-centre');

      expect(entries, isNotEmpty);

      final evening = entries.where((e) => e.startTime.compareTo('17:00') >= 0);
      expect(evening, isNotEmpty, reason: 'Expected evening swims in season expansion');

      for (final entry in entries.where((e) => e.date == OttawaTime.todayDate())) {
        expect(
          entry.startTime.compareTo(entry.endTime),
          lessThan(0),
          reason: '${entry.rawCategory} ${entry.startTime}-${entry.endTime}',
        );
      }
    });
  });
}
