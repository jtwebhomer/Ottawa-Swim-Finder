import 'package:flutter_test/flutter_test.dart';
import 'package:ottawa_swim_finder/data/services/sync_safety_guard.dart';
import 'package:ottawa_swim_finder/domain/entities/schedule_entry.dart';

void main() {
  final guard = SyncSafetyGuard();

  test('rejects empty write when cached data exists', () {
    final decision = guard.evaluate(
      facilityId: 'jack-purcell-community-centre',
      newEntries: [],
      existingEntryCount: 42,
      htmlSwimMentions: 5,
      httpStatus: 200,
    );
    expect(decision.allowWrite, isFalse);
  });

  test('allows write when new entries are valid', () {
    final decision = guard.evaluate(
      facilityId: 'test',
      newEntries: const [
        ScheduleEntry(
          facilityId: 'test',
          category: 'public_swim',
          scheduleType: 'expanded',
          date: '2026-06-22',
          startTime: '18:00',
          endTime: '19:00',
        ),
      ],
      existingEntryCount: 0,
      htmlSwimMentions: 3,
      httpStatus: 200,
    );
    expect(decision.allowWrite, isTrue);
  });

  test('rejects HTTP error results', () {
    final decision = guard.evaluate(
      facilityId: 'test',
      newEntries: [],
      existingEntryCount: 10,
      htmlSwimMentions: 0,
      httpStatus: 403,
    );
    expect(decision.allowWrite, isFalse);
  });
}
