import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../data/services/qa_checklist_service.dart';
import '../../di/injection.dart';
import '../providers/app_state.dart';

/// Data quality dashboard and scrape diagnostics.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  List<QaTestItem> _qaTests = [];
  bool _qaLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQa();
  }

  Future<void> _loadQa() async {
    final tests = await getIt<QaChecklistService>().loadAll();
    if (mounted) {
      setState(() {
        _qaTests = tests;
        _qaLoading = false;
      });
    }
  }

  Future<void> _setQaStatus(String id, QaTestStatus status) async {
    await getIt<QaChecklistService>().setStatus(id, status);
    await _loadQa();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final errors = state.scrapeLogs.where((l) => l.status == 'error').toList();
    final blocked =
        state.scrapeLogs.where((l) => l.status == 'blocked').toList();
    final parseEmpty =
        state.scrapeLogs.where((l) => l.status == 'parse_empty').toList();
    final rejected =
        state.scrapeLogs.where((l) => l.status == 'rejected').toList();
    final health = state.syncHealth;
    final parser = state.parserHealth;
    final duration = health?.lastSyncDurationMs;
    final durationLabel = duration == null
        ? '—'
        : duration >= 1000
            ? '${(duration / 1000).toStringAsFixed(1)} s'
            : '$duration ms';

    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostics')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Parser Health', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row('Parser Health Status', parser?.status ?? 'Unknown'),
                  _row(
                    'Last Successful Ottawa Parse',
                    _formatTs(parser?.lastSuccessfulParseAt),
                  ),
                  _row('Facilities Parsed', parser?.facilitiesLabel ?? '—'),
                  _row(
                    'Future Sessions Parsed',
                    '${parser?.futureSessionsParsed ?? state.futureSessionCount}',
                  ),
                  _row(
                    'Unknown Categories',
                    '${parser?.unknownCategoryCount ?? state.unknownCategories.length}',
                  ),
                  if (parser?.anomalyWarning != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Warning: ${parser!.anomalyWarning}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Sync Health', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row('Sync Status', health?.lastSyncStatus ?? '—'),
                  _row(
                    'Success Rate',
                    health?.lastSuccessRate != null
                        ? '${(health!.lastSuccessRate! * 100).toStringAsFixed(0)}%'
                        : '—',
                  ),
                  _row(
                    'Blocked Facilities',
                    '${health?.lastBlockedCount ?? state.blockedFacilityNames.length}',
                  ),
                  if (state.blockedFacilityNames.isNotEmpty)
                    _row(
                      'Blocked (last sync)',
                      state.blockedFacilityNames.join(', '),
                    ),
                  _row(
                    'Stale Facilities',
                    '${state.staleFacilityCount}',
                  ),
                  _row(
                    'Last Fully Clean Sync',
                    _formatTs(health?.lastFullyCleanSyncAt),
                  ),
                  _row(
                    'Facilities Updated',
                    '${health?.lastUpdatedFacilities ?? 0}',
                  ),
                  _row(
                    'Facilities Unchanged',
                    '${health?.lastSkippedFacilities ?? 0}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Facility Inclusion Trace',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (state.facilityCatalogAudit == null)
            const Card(
              child: ListTile(
                title: Text('Run sync or refresh to build inclusion trace'),
              ),
            )
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _row(
                      'Source indoor (enumerated)',
                      '${state.facilityCatalogAudit!.sourceIndoorEnumerated}',
                    ),
                    _row(
                      'Source indoor (marketing)',
                      '${state.facilityCatalogAudit!.sourceIndoorMarketing}',
                    ),
                    _row(
                      'Discovered live',
                      '${state.facilityCatalogAudit!.discoveredCount}',
                    ),
                    _row('In database', '${state.facilityCatalogAudit!.dbCount}'),
                    _row('Shown in UI', '${state.facilityCatalogAudit!.uiCount}'),
                    const SizedBox(height: 8),
                    Text(state.facilityCatalogAudit!.explanation),
                  ],
                ),
              ),
            ),
            ...state.facilityCatalogAudit!.traces.map(
              (trace) => Card(
                child: ListTile(
                  dense: true,
                  title: Text(trace.name),
                  subtitle: Text(
                    trace.summaryLine(),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: trace.included
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.warning_amber, color: Colors.orange),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text('Data Quality', style: Theme.of(context).textTheme.titleLarge),

          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row('Facilities', '${state.facilities.length}'),
                  _row('Future Sessions', '${state.futureSessionCount}'),
                  _row('Total Sessions', '${state.totalSessionCount}'),
                  _row('Unknown Types', '${state.unknownCategories.length}'),
                  _row('Scrape Errors', '${state.scrapeErrorCount}'),
                  _row('HTTP Errors (last sync)', '${health?.lastErrorCount ?? 0}'),
                  _row('Last Sync Status', health?.lastSyncStatus ?? '—'),
                  _row('Last Sync Duration', durationLabel),
                  _row('Data Age', state.dataAgeLabel),
                  _row(
                    'Last Successful Sync',
                    _formatTs(health?.lastSuccessfulSyncAt),
                  ),
                  _row('Last Attempt', _formatTs(health?.lastSyncAt)),
                  _row('Current App Version', state.appVersion),
                  _row(
                    'Last Synced App Version',
                    state.lastSyncedAppVersion ?? '—',
                  ),
                ],
              ),
            ),
          ),
          if (state.lastSyncRootCause != null)
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              margin: const EdgeInsets.only(top: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Last sync root cause',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(state.lastSyncRootCause!),
                  ],
                ),
              ),
            ),
          if (state.lastFacilityDiagnostics.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Facility sync diagnostics (last run)',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            ...state.lastFacilityDiagnostics.map(
              (d) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    d.debugLine(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                  ),
                ),
              ),
            ),
          ],
          if (blocked.isNotEmpty)
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              margin: const EdgeInsets.only(top: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${blocked.length} facility page(s) blocked by ottawa.ca — '
                  'cached data preserved.',
                ),
              ),
            ),
          if (parseEmpty.isNotEmpty)
            Card(
              margin: const EdgeInsets.only(top: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${parseEmpty.length} facility page(s) returned empty parse — '
                  'cached data preserved.',
                ),
              ),
            ),
          if (state.syncAnomalyWarning != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              margin: const EdgeInsets.only(top: 12),
              child: ListTile(
                title: const Text('Sync anomaly'),
                subtitle: Text(state.syncAnomalyWarning!),
              ),
            ),
          const SizedBox(height: 16),
          Text('QA Checklist', style: Theme.of(context).textTheme.titleLarge),
          if (_qaLoading)
            const LinearProgressIndicator()
          else
            ..._qaTests.map(
              (test) => Card(
                child: ListTile(
                  title: Text(test.label),
                  subtitle: Text(test.status.name),
                  trailing: SegmentedButton<QaTestStatus>(
                    segments: const [
                      ButtonSegment(
                        value: QaTestStatus.pass,
                        label: Text('Pass'),
                      ),
                      ButtonSegment(
                        value: QaTestStatus.fail,
                        label: Text('Fail'),
                      ),
                      ButtonSegment(
                        value: QaTestStatus.notTested,
                        label: Text('N/T'),
                      ),
                    ],
                    selected: {test.status},
                    onSelectionChanged: (s) =>
                        _setQaStatus(test.id, s.first),
                  ),
                ),
              ),
            ),
          if (errors.isNotEmpty)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              margin: const EdgeInsets.only(top: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${errors.length} scrape error(s) — cached data preserved.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          if (state.validationWarnings.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Validation (${state.validationWarnings.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ...state.validationWarnings.take(20).map(
                  (w) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.warning_amber),
                    title: Text(w.message),
                    subtitle: Text(w.code),
                  ),
                ),
          ],
          if (rejected.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Rejected Writes (${rejected.length})'),
            ...rejected.take(5).map(
                  (log) => ListTile(
                    dense: true,
                    title: Text(log.facilityId ?? 'global'),
                    subtitle: Text(log.message ?? ''),
                  ),
                ),
          ],
          const SizedBox(height: 16),
          Text('Scrape Log', style: Theme.of(context).textTheme.titleLarge),
          ...state.scrapeLogs.take(30).map((log) {
            final time = DateTime.fromMillisecondsSinceEpoch(log.createdAt);
            return ListTile(
              dense: true,
              title: Text('${log.facilityId ?? 'global'} — ${log.status}'),
              subtitle: Text(DateFormat.yMMMd().add_jm().format(time)),
            );
          }),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 180, child: Text(label)),
            Expanded(
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );

  String _formatTs(DateTime? dt) =>
      dt == null ? '—' : DateFormat.yMMMd().add_jm().format(dt);
}
