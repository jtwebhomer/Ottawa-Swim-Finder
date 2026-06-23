import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../domain/entities/sync_status.dart';
import '../providers/app_state.dart';

enum SyncIndicatorState { syncing, upToDate, partial }

/// Minimal app-bar sync affordance — tap for details, never blocks content.
class SyncStatusIndicator extends StatelessWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final indicator = state.syncIndicatorState;

    return IconButton(
      tooltip: 'Schedule sync status',
      onPressed: () => _showDetails(context, state),
      icon: switch (indicator) {
        SyncIndicatorState.syncing => const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        SyncIndicatorState.upToDate => Icon(
            Icons.check_circle_outline,
            color: Theme.of(context).colorScheme.primary,
          ),
        SyncIndicatorState.partial => Icon(
            Icons.cloud_queue,
            color: Theme.of(context).colorScheme.tertiary,
          ),
      },
    );
  }

  void _showDetails(BuildContext context, AppState state) {
    final freshness = state.syncFreshness;
    final last = state.lastSuccessfulSyncAt;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Schedules', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (state.isSyncing || state.backgroundSyncActive)
                const ListTile(
                  leading: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text('Updating in the background'),
                  subtitle: Text('Your swims stay available while we refresh.'),
                )
              else if (last != null)
                ListTile(
                  leading: const Icon(Icons.schedule),
                  title: const Text('Last updated'),
                  subtitle: Text(DateFormat.yMMMd().add_jm().format(last)),
                )
              else
                const ListTile(
                  leading: Icon(Icons.offline_bolt),
                  title: Text('Showing bundled schedules'),
                  subtitle: Text('Live refresh will run when you\'re online.'),
                ),
              if (freshness != null)
                ListTile(
                  leading: const Icon(Icons.pool),
                  title: Text(freshness.completenessLabel),
                  subtitle: Text(
                    '${freshness.facilitiesWithSchedules} of '
                    '${freshness.totalSwimFacilities} pools have schedules',
                  ),
                ),
              if (state.syncProgress != null)
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: Text(
                    '${state.syncProgress!.updated} facilities refreshed this run',
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: state.isSyncing ? null : () {
                  Navigator.pop(ctx);
                  state.manualSync();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh now'),
              ),
            ],
          ),
        );
      },
    );
  }
}

extension on AppState {
  SyncIndicatorState get syncIndicatorState {
    if (isSyncing || backgroundSyncActive) {
      return SyncIndicatorState.syncing;
    }
    final completeness = syncFreshness?.completenessPercent ?? 0;
    if (lastSyncStatus == SyncStatus.partialSuccess || completeness < 100) {
      return SyncIndicatorState.partial;
    }
    return SyncIndicatorState.upToDate;
  }
}
