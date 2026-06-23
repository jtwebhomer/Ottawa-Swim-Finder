import 'package:flutter/material.dart';

import '../../domain/entities/sync_progress.dart';
import '../providers/app_state.dart';

/// Live progress during background Ottawa.ca sync.
class SyncProgressBanner extends StatelessWidget {
  const SyncProgressBanner({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (!state.isSyncing || state.syncProgress == null) {
      return const SizedBox.shrink();
    }

    final progress = state.syncProgress!;
    final theme = Theme.of(context);
    final total = progress.totalFacilities;
    final updated = progress.updated;
    final blocked = progress.blocked;
    final pending = progress.pending;
    final phaseLabel = switch (progress.phase) {
      SyncPhase.fetching => 'Fetching schedules',
      SyncPhase.validating => 'Validating data',
      SyncPhase.committing => 'Saving updates',
    };

    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    state.backgroundSyncActive
                        ? 'Updating schedules in background…'
                        : 'Updating swim schedules…',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(phaseLabel, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text('$updated of $total facilities refreshed this run'),
            if (blocked > 0)
              Text(
                'Some pools will refresh on the next attempt',
                style: TextStyle(color: theme.colorScheme.tertiary),
              ),
            if (pending > 0) Text('$pending remaining in this batch'),
            if (progress.currentFacilityName != null) ...[
              const SizedBox(height: 4),
              Text(
                progress.currentFacilityName!,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
