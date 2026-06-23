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
    this.isStale = false,
    this.onTap,
    this.onSave,
    this.onExport,
  });

  final ScheduleEntry entry;
  final bool highlight;
  final bool showFacility;
  final bool isStale;
  final VoidCallback? onTap;
  final VoidCallback? onSave;
  final VoidCallback? onExport;

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
            Text(
              SwimSessionPresenter.sessionTitle(entry),
              style: theme.textTheme.titleMedium,
            ),
            if (entry.rawCategory != null &&
                entry.rawCategory!.trim().isNotEmpty &&
                entry.rawCategory!.trim().toLowerCase() !=
                    SwimCategories.labelFor(entry.category).toLowerCase())
              Text(
                'Type: ${SwimCategories.labelFor(entry.category)}',
                style: theme.textTheme.bodySmall,
              ),
            if (showFacility && entry.facilityName != null)
              Text(entry.facilityName!),
            if (entry.distanceKm != null)
              Text('${entry.distanceKm!.toStringAsFixed(1)} km away'),
            if (isStale)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: Colors.orange.shade800,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'May be outdated',
                      style: TextStyle(
                        color: Colors.orange.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onExport != null)
              IconButton(
                icon: const Icon(Icons.event),
                tooltip: 'Export to calendar',
                onPressed: onExport,
              ),
            if (onSave != null)
              IconButton(
                icon: const Icon(Icons.bookmark_add_outlined),
                tooltip: 'Save swim',
                onPressed: onSave,
              ),
            if (onTap != null) const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
