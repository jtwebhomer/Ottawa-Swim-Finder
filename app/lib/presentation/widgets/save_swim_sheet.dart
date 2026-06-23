import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../data/services/swim_query_service.dart';
import '../../domain/entities/schedule_entry.dart';

/// Bottom sheet for saving a swim with optional reminder and recurring pattern.
Future<void> showSaveSwimSheet(
  BuildContext context, {
  required ScheduleEntry entry,
  required Future<void> Function({int? reminderMinutes, bool asRecurring}) onSave,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      int? reminderMinutes;
      var asRecurring = false;
      final canRecur = entry.dayOfWeek != null;

      return StatefulBuilder(
        builder: (context, setState) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Save swim',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '${SwimCategories.displayName(category: entry.category, rawName: entry.rawCategory)}\n'
                  '${entry.facilityName ?? entry.facilityId} · ${entry.startTime}–${entry.endTime}',
                ),
                if (canRecur) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Save as weekly pattern'),
                    subtitle: entry.dayOfWeek != null
                        ? Text(
                            'Every ${_weekdayLabel(entry.dayOfWeek!)} at ${entry.startTime}',
                          )
                        : null,
                    value: asRecurring,
                    onChanged: (v) => setState(() => asRecurring = v),
                  ),
                ],
                const SizedBox(height: 8),
                DropdownButtonFormField<int?>(
                  initialValue: reminderMinutes,
                  decoration: const InputDecoration(
                    labelText: 'Reminder (optional)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('No reminder')),
                    ...ReminderOptions.values.map(
                      (m) => DropdownMenuItem(
                        value: m,
                        child: Text(ReminderOptions.labelFor(m)),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => reminderMinutes = v),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await onSave(
                      reminderMinutes: reminderMinutes,
                      asRecurring: asRecurring,
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

String _weekdayLabel(int dayOfWeek) {
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  if (dayOfWeek >= 1 && dayOfWeek <= 7) return days[dayOfWeek - 1];
  return 'weekday $dayOfWeek';
}
