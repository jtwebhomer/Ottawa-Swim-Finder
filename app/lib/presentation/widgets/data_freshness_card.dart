import 'package:flutter/material.dart';

import 'package:intl/intl.dart';

import '../../data/services/schedule_trust_resolver.dart';
import '../../domain/entities/schedule_trust_status.dart';
import '../../domain/entities/sync_status.dart';
import '../providers/app_state.dart';

/// Visible on Home — explains schedule data origin and verification coverage.
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
    final freshness = state.syncFreshness;
    final trust = state.trustSummary ?? freshness?.trustSummary;
    final status = state.lastSyncStatus;
    final lastVerified = freshness?.lastVerifiedAt ?? state.lastSuccessfulSyncAt;

    final isPartial = status == SyncStatus.partialSuccess;
    final isFailed = status == SyncStatus.failed;
    final syncBlocked = freshness?.syncBlocked ?? false;

    final headline = state.backgroundSyncActive
        ? 'Updating schedules in background…'
        : _headline(
            status: status,
            trust: trust,
            lastVerified: lastVerified,
            syncBlocked: syncBlocked,
            lastSyncEngine: state.lastSyncEngine,
          );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  state.isOnline ? Icons.verified_user_outlined : Icons.cloud_off,
                  color: isPartial || isFailed
                      ? theme.colorScheme.tertiary
                      : state.isOnline
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Data Status',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (trust != null && trust.verified > 0)
                  Chip(
                    label: Text('${trust.verified} verified'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              headline,
              style: theme.textTheme.bodyLarge,
            ),
            if (trust != null) ...[
              const SizedBox(height: 8),
              Text(
                _trustSummaryLine(trust),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (freshness?.seedBundledAt != null)
              Text(
                'Bundled snapshot: ${DateFormat.yMMMd().format(freshness!.seedBundledAt!)}',
                style: theme.textTheme.bodySmall,
              ),
            if (lastVerified != null)
              Text(
                state.lastSyncEngine == 'API'
                    ? 'Live verified schedule · updated ${_relativeAge(lastVerified)}'
                    : 'Schedules verified ${_relativeAge(lastVerified)}',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Text(
              '${state.facilities.length} facilities · '
              '${state.futureSessionCount} future swims · '
              '${freshness?.facilitiesWithSchedules ?? 0} with schedules'
              '${state.staleFacilityCount > 0 ? ' · ${state.staleFacilityCount} awaiting refresh' : ''}',
              style: theme.textTheme.bodySmall,
            ),
            if (state.syncMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                state.syncMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
                      _showDetails ? 'Hide details' : 'Show pending facilities',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (_showDetails) ...[
                const SizedBox(height: 8),
                Text(
                  'These facilities still use bundled or cached data:',
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

  String _headline({
    required SyncStatus? status,
    required ScheduleTrustSummary? trust,
    required DateTime? lastVerified,
    required bool syncBlocked,
    required String? lastSyncEngine,
  }) {
    if (syncBlocked && (trust?.fixture ?? 0) > 0) {
      return 'Using bundled schedule data. Live verification will occur automatically.';
    }
    if (syncBlocked || status == SyncStatus.failed) {
      return 'Live updates temporarily unavailable. Showing last verified schedules.';
    }
    if (lastSyncEngine == 'API') {
      return 'Live verified schedule';
    }
    if (lastVerified != null) {
      return 'Updated ${_relativeAge(lastVerified)}';
    }
    if ((trust?.fixture ?? 0) > 0) {
      return 'Showing bundled Ottawa schedule snapshots';
    }
    return 'Schedule data loading…';
  }

  String _trustSummaryLine(ScheduleTrustSummary trust) {
    final parts = <String>[];
    if (trust.verified > 0) {
      parts.add(
        '${trust.verified} facilit${trust.verified == 1 ? 'y' : 'ies'} verified',
      );
    }
    if (trust.fixture > 0) {
      parts.add(
        '${trust.fixture} facilit${trust.fixture == 1 ? 'y' : 'ies'} using bundled schedule data',
      );
    }
    if (trust.cached > 0) {
      parts.add('${trust.cached} cached');
    }
    if (trust.stale > 0) {
      parts.add('${trust.stale} may be outdated');
    }
    if (trust.unverified > 0) {
      parts.add('${trust.unverified} awaiting schedules');
    }
    return parts.join(' · ');
  }

  String _relativeAge(DateTime last) {
    final days = DateTime.now().difference(last).inDays;
    if (days == 0) return 'today';
    if (days == 1) return '1 day ago';
    return '$days days ago';
  }
}
