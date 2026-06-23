import 'package:flutter_test/flutter_test.dart';
import 'package:ottawa_swim_finder/core/constants/sync_thresholds.dart';
import 'package:ottawa_swim_finder/data/services/blocked_page_detector.dart';
import 'package:ottawa_swim_finder/domain/entities/sync_status.dart';

void main() {
  group('BlockedPageDetector', () {
    test('detects pardon our interruption', () {
      const html = '<html><body>Pardon Our Interruption</body></html>';
      final result = BlockedPageDetector.check(html);
      expect(result.isBlocked, isTrue);
      expect(result.signaturesMatched, contains('pardon_our_interruption'));
    });

    test('detects cloudflare and captcha', () {
      const html = '<html>Cloudflare captcha challenge</html>';
      final result = BlockedPageDetector.check(html);
      expect(result.isBlocked, isTrue);
    });

    test('passes valid swim table HTML', () {
      const html = '''
<table><caption>Pool swim - June 1 to August 31</caption>
<thead><tr><th></th><th>Monday</th></tr></thead>
<tbody><tr><th>Lane swim</th><td>8 - 9 am</td></tr></tbody></table>
''';
      final result = BlockedPageDetector.check(html);
      expect(result.isBlocked, isFalse);
      expect(result.hasScheduleTables, isTrue);
    });

    test('flags long HTML without swim tables', () {
      final html = '<html>${'x' * 1000}</html>';
      final result = BlockedPageDetector.check(html);
      expect(result.isBlocked, isTrue);
      expect(result.signaturesMatched, contains('missing_schedule_tables'));
    });
  });

  group('SyncStatus', () {
    test('success when all facilities updated without errors', () {
      final status = SyncStatus.fromCounts(
        totalFacilities: 20,
        updated: 15,
        skipped: 5,
        blocked: 0,
        parseEmpty: 0,
        parseRejected: 0,
        networkFailures: 0,
        pipelineCrashes: 0,
        antiCorruptionTriggered: false,
        scheduleCountAfter: 500,
      );
      expect(status, SyncStatus.success);
    });

    test('partial when blocked but cached data remains', () {
      final status = SyncStatus.fromCounts(
        totalFacilities: 20,
        updated: 0,
        skipped: 0,
        blocked: 8,
        parseEmpty: 0,
        parseRejected: 0,
        networkFailures: 0,
        pipelineCrashes: 0,
        antiCorruptionTriggered: false,
        scheduleCountAfter: 500,
      );
      expect(status, SyncStatus.partialSuccess);
    });

    test('failed on first install when all blocked', () {
      final status = SyncStatus.fromCounts(
        totalFacilities: 20,
        updated: 0,
        skipped: 0,
        blocked: 20,
        parseEmpty: 0,
        parseRejected: 0,
        networkFailures: 0,
        pipelineCrashes: 0,
        antiCorruptionTriggered: false,
        scheduleCountAfter: 0,
      );
      expect(status, SyncStatus.failed);
    });

    test('failed when anti-corruption triggers', () {
      final status = SyncStatus.fromCounts(
        totalFacilities: 20,
        updated: 0,
        skipped: 0,
        blocked: 15,
        parseEmpty: 0,
        parseRejected: 0,
        networkFailures: 5,
        pipelineCrashes: 0,
        antiCorruptionTriggered: true,
        scheduleCountAfter: 500,
      );
      expect(status, SyncStatus.failed);
    });
  });

  group('Anti-corruption threshold', () {
    test('60% minimum success rate constant', () {
      expect(SyncThresholds.minGlobalSuccessRate, 0.60);
    });
  });
}
