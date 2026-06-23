import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/entities/schedule_entry.dart';
import 'swim_session_presenter.dart';

class ScheduleSessionCard extends StatelessWidget {
  const ScheduleSessionCard({
    super.key,
    required this.entry,
    this.highlight = false,
    this.showFacility = false,
    this.onTap,
  });

  final ScheduleEntry entry;
  final bool highlight;
  final bool showFacility;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final status = SwimSessionPresenter.statusFor(entry);
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: highlight
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
          : null,
      child: ListTile(
        onTap: onTap,
        title: Text(
          SwimSessionPresenter.formatRange(entry),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(SwimSessionPresenter.sessionTitle(entry)),
            Text(
              SwimCategories.labelFor(entry.category),
              style: theme.textTheme.bodySmall,
            ),
            if (showFacility && entry.facilityName != null)
              Text(entry.facilityName!),
            const SizedBox(height: 4),
            Text(
              status.label,
              style: TextStyle(
                color: switch (status.status) {
                  SwimSessionStatus.active => Colors.green.shade700,
                  SwimSessionStatus.upcoming => theme.colorScheme.primary,
                  SwimSessionStatus.ended => theme.colorScheme.outline,
                },
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: onTap != null ? const Icon(Icons.chevron_right) : null,
      ),
    );
  }
}
