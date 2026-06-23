import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../data/services/swim_query_service.dart';
import '../providers/app_state.dart';
import 'facility_screen.dart';

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Saved Swims')),
      body: state.savedSwims.isEmpty
          ? const Center(
              child: Text(
                'Save swims from Home, Calendar, or Find Swim.\n'
                'Tap the bookmark icon on any session.',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.savedSwims.length,
              itemBuilder: (context, index) {
                final saved = state.savedSwims[index];
                return Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        title: Text(
                          SwimCategories.displayName(
                            category: saved.category,
                            rawName: saved.rawCategory,
                          ),
                        ),
                        subtitle: Text(
                          '${saved.facilityName ?? saved.facilityId}\n'
                          '${saved.isRecurring ? saved.patternLabel : saved.date} · '
                          '${saved.startTime}–${saved.endTime}',
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => state.removeSavedSwim(saved.id!),
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                FacilityScreen(facilityId: saved.facilityId),
                          ),
                        ),
                      ),
                      if (saved.isRecurring && saved.upcomingOccurrences.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: Text(
                            'Upcoming: ${saved.upcomingOccurrences.take(3).map((o) => '${o.date} ${o.startTime}').join(' · ')}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<int?>(
                                initialValue: saved.reminderMinutes,
                                decoration: const InputDecoration(
                                  labelText: 'Reminder',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: null,
                                    child: Text('None'),
                                  ),
                                  ...ReminderOptions.values.map(
                                    (m) => DropdownMenuItem(
                                      value: m,
                                      child: Text(ReminderOptions.labelFor(m)),
                                    ),
                                  ),
                                ],
                                onChanged: (v) =>
                                    state.updateSavedSwimReminder(saved.id!, v),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
