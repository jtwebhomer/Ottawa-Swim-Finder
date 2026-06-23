import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/sync_status.dart';
import '../providers/app_state.dart';

/// Visible on Home launch — confirms schedules exist and sync succeeded.
class DataFreshnessCard extends StatefulWidget {
  const DataFreshnessCard({super.key, required this.state});

  final AppState state;

  @override
  State<DataFreshnessCard> createState() => _DataFreshnessCardState();
}

class _DataFreshnessCardState extends State<DataFreshnessCard> {
  bool _showDetails = false;

  AppState get state => widget.state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = state.lastSuccessfulSyncAt;
    final status = state.lastSyncStatus;
    final isPartial = status == SyncStatus.partialSuccess;
    final isFailed = status == SyncStatus.failed;

    final headline = switch (status) {
      SyncStatus.success when last != null =>
        'Updated ${_relativeAge(last)} — All facilities synced',
      SyncStatus.partialSuccess =>
        '⚠ Partial update — some facilities could not be refreshed',
      SyncStatus.failed =>
        'Sync incomplete — showing last known schedules',
      _ => last == null ? 'Never synced' : 'Updated ${_relativeAge(last)}',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  state.isOnline ? Icons.cloud_done : Icons.cloud_off,
                  color: isPartial || isFailed
                      ? theme.colorScheme.error
                      : state.isOnline
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Data Freshness', style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              headline,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: isPartial || isFailed ? theme.colorScheme.error : null,
              ),
            ),
            if (last != null)
              Text(
                'Last Updated: ${DateFormat.yMMMd().add_jm().format(last)}',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Text(
              '${state.facilities.length} facilities · '
              '${state.futureSessionCount} future swims'
              '${state.staleFacilityCount > 0 ? ' · ${state.staleFacilityCount} stale' : ''}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            if (isPartial && state.staleFacilityNames.isNotEmpty) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () => setState(() => _showDetails = !_showDetails),
                child: Row(
                  children: [
                    Icon(
                      _showDetails ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _showDetails ? 'Hide details' : 'Show stale facilities',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (_showDetails) ...[
                const SizedBox(height: 8),
                Text(
                  'These facilities could not be refreshed. Showing last known data:',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                ...state.staleFacilityNames.take(8).map(
                      (name) => Text('• $name', style: theme.textTheme.bodySmall),
                    ),
                if (state.staleFacilityNames.length > 8)
                  Text(
                    '…and ${state.staleFacilityNames.length - 8} more',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ],
            if (state.syncAnomalyWarning != null) ...[
              const SizedBox(height: 8),
              Text(
                state.syncAnomalyWarning!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _relativeAge(DateTime last) {
    final days = DateTime.now().difference(last).inDays;
    if (days == 0) return 'today';
    if (days == 1) return '1 day ago';
    return '$days days ago';
  }
}
