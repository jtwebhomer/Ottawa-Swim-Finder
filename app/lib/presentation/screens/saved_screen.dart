import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../data/services/swim_query_service.dart';
import '../../domain/entities/saved_swim.dart';
import '../providers/app_state.dart';
import '../widgets/navigation_launch_button.dart';
import 'facility_screen.dart';

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Saved')),
      body: state.savedSwims.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bookmark_border,
                      size: 56,
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No saved swims yet',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap the bookmark on any swim card to save it here — '
                      'like starred places in Maps.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: state.savedSwims.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final saved = state.savedSwims[index];
                final facility = state.facilityFor(saved.facilityId);
                final next = _nextOccurrenceLabel(saved);

                return Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    saved.facilityName ?? facility?.name ?? 'Pool',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    SwimCategories.displayName(
                                      category: saved.category,
                                      rawName: saved.rawCategory,
                                    ),
                                    style: theme.textTheme.bodyLarge,
                                  ),
                                  Text(
                                    next,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              tooltip: 'Remove',
                              onPressed: () => state.removeSavedSwim(saved.id!),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              saved.reminderMinutes != null
                                  ? Icons.notifications_active_outlined
                                  : Icons.notifications_none_outlined,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              saved.reminderMinutes != null
                                  ? 'Reminder ${ReminderOptions.labelFor(saved.reminderMinutes!)}'
                                  : 'No reminder',
                              style: theme.textTheme.bodySmall,
                            ),
                            const Spacer(),
                            if (facility?.latitude != null &&
                                facility?.longitude != null)
                              NavigationLaunchButton(
                                latitude: facility!.latitude!,
                                longitude: facility.longitude!,
                                title: facility.name,
                                facilityId: facility.id,
                                compact: true,
                              ),
                            TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FacilityScreen(
                                    facilityId: saved.facilityId,
                                  ),
                                ),
                              ),
                              child: const Text('View pool'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _nextOccurrenceLabel(SavedSwim saved) {
    if (saved.isRecurring) {
      final next = saved.upcomingOccurrences.isNotEmpty
          ? saved.upcomingOccurrences.first
          : null;
      if (next != null) {
        return 'Next: ${next.date} · ${_format12(next.startTime)}';
      }
      return saved.patternLabel;
    }
    return '${saved.date} · ${_format12(saved.startTime)}–${_format12(saved.endTime)}';
  }

  String _format12(String time24) {
    final parts = time24.split(':');
    if (parts.length != 2) return time24;
    var hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final period = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    return '$hour:${minute.toString().padLeft(2, '0')} $period';
  }
}
