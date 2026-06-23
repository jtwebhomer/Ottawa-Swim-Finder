import 'package:flutter/material.dart';

import '../providers/app_state.dart';

/// Live progress during an active Ottawa.ca sync.
class SyncProgressBanner extends StatelessWidget {
  const SyncProgressBanner({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final progress = state.syncProgress;
    if (!state.isSyncing || progress == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final total = progress.totalFacilities;
    final updated = progress.updated;
    final blocked = progress.blocked;
    final pending = progress.pending;

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
                    'Updating swim schedules…',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('$updated of $total facilities updated'),
            if (blocked > 0)
              Text(
                '$blocked could not be reached (will retry)',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            if (pending > 0) Text('$pending remaining'),
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
