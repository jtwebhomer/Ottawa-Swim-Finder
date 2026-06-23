import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../providers/app_state.dart';

class DebugScreen extends StatelessWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final errors = state.scrapeLogs.where((l) => l.status == 'error').toList();
    final rejected =
        state.scrapeLogs.where((l) => l.status == 'rejected').toList();
    final health = state.syncHealth;

    return Scaffold(
      appBar: AppBar(title: const Text('Debug / Admin')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (errors.isNotEmpty)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${errors.length} scrape error(s) — cached data preserved on failure.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          Text('System Health', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _healthRow('Last sync status', health?.lastSyncStatus ?? '—'),
                  _healthRow(
                    'Last sync',
                    _formatTs(health?.lastSyncAt),
                  ),
                  _healthRow(
                    'Last successful sync',
                    _formatTs(health?.lastSuccessfulSyncAt),
                  ),
                  _healthRow(
                    'Schedule rows (before → after)',
                    '${health?.lastScheduleCountBefore ?? '—'} → ${health?.lastScheduleCountAfter ?? '—'}',
                  ),
                  _healthRow(
                    'Facilities updated / skipped',
                    '${health?.lastUpdatedFacilities ?? '—'} / ${health?.lastSkippedFacilities ?? '—'}',
                  ),
                  _healthRow(
                    'HTTP errors (403 count)',
                    '${health?.lastErrorCount ?? '—'} (${health?.lastHttp403Count ?? 0} forbidden)',
                  ),
                  _healthRow(
                    'UI timeline / active now',
                    '${state.timeline.length} / ${state.activeSwims.length}',
                  ),
                ],
              ),
            ),
          ),
          if (rejected.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Rejected Writes (${rejected.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...rejected.take(5).map(
                  (log) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.shield, color: Colors.orange),
                    title: Text(log.facilityId ?? ''),
                    subtitle: Text(log.message ?? ''),
                  ),
                ),
          ],
          if (state.validationWarnings.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Validation Warnings (${state.validationWarnings.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ...state.validationWarnings.take(10).map(
                  (w) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.warning_amber, color: Colors.orange),
                    title: Text(w.message),
                    subtitle: Text(w.code),
                  ),
                ),
          ],
          if (state.rawNameAudit.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Raw Session Names', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ...state.rawNameAudit.take(15).map(
                  (entry) => ListTile(
                    dense: true,
                    title: Text(entry.rawName),
                    subtitle: Text(
                      '${entry.count}× → ${entry.normalizedType}\n${entry.facilities.take(3).join(', ')}',
                    ),
                    isThreeLine: true,
                  ),
                ),
          ],
          const SizedBox(height: 16),
          const SizedBox(height: 8),
          ...state.scrapeLogs.map((log) {
            final time = DateTime.fromMillisecondsSinceEpoch(log.createdAt);
            return Card(
              child: ListTile(
                leading: Icon(
                  log.status == 'error'
                      ? Icons.error
                      : log.status == 'rejected'
                          ? Icons.shield
                          : log.status == 'skipped'
                              ? Icons.skip_next
                              : Icons.check_circle,
                  color: log.status == 'error'
                      ? Colors.red
                      : log.status == 'rejected'
                          ? Colors.orange
                          : Colors.green,
                ),
                title: Text('${log.facilityId ?? 'global'} — ${log.status}'),
                subtitle: Text(
                  '${DateFormat.yMMMd().add_jm().format(time)}\n${log.message ?? ''}',
                ),
                isThreeLine: true,
                trailing: log.htmlSnapshotPath != null
                    ? const Icon(Icons.html)
                    : null,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _healthRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 160, child: Text(label)),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
          ],
        ),
      );

  String _formatTs(DateTime? dt) =>
      dt == null ? '—' : DateFormat.yMMMd().add_jm().format(dt);
}
