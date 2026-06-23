import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../data/services/map_tile_cache_service.dart';
import '../../data/services/navigation_service.dart';
import '../../di/injection.dart';
import '../providers/app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  MapCacheInfo? _cacheInfo;
  String? _preferredNavApp;
  bool _cachingTiles = false;
  double _cacheProgress = 0;

  @override
  void initState() {
    super.initState();
    _loadMapSettings();
  }

  Future<void> _loadMapSettings() async {
    final tileCache = getIt<MapTileCacheService>();
    final nav = getIt<NavigationService>();
    final info = await tileCache.getCacheInfo();
    final preferred = await nav.getPreferredMapType();
    final maps = await nav.getInstalledMaps();
    String? preferredLabel;
    if (preferred != null && preferred.isNotEmpty) {
      preferredLabel = maps
          .where((m) => m.mapType.name == preferred)
          .map((m) => m.mapName)
          .firstOrNull;
    }
    if (mounted) {
      setState(() {
        _cacheInfo = info;
        _preferredNavApp = preferredLabel ?? 'Not set (choose on first navigate)';
      });
    }
  }

  Future<void> _downloadOttawaTiles() async {
    setState(() {
      _cachingTiles = true;
      _cacheProgress = 0;
    });

    final tileCache = getIt<MapTileCacheService>();
    try {
      await for (final progress in tileCache.warmCacheForOttawa()) {
        if (mounted) setState(() => _cacheProgress = progress);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ottawa map tiles cached for offline use')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tile caching failed: $e')),
        );
      }
    } finally {
      await _loadMapSettings();
      if (mounted) setState(() => _cachingTiles = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final errors = state.scrapeLogs.where((l) => l.status == 'error').length;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          if (!state.isOnline)
            Card(
              margin: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: const ListTile(
                leading: Icon(Icons.cloud_off),
                title: Text('Offline mode'),
                subtitle: Text(
                  'Schedules load from cache. Connect to sync updates.',
                ),
              ),
            ),
          if (errors > 0)
            Card(
              margin: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                title: Text(
                  '$errors scrape error${errors == 1 ? '' : 's'} — schedules may be missing',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'See Diagnostics for details. Try Manual Sync when online.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                onTap: () => Navigator.pushNamed(context, '/diagnostics'),
              ),
            ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sync Status', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _syncRow('Last Updated', _formatTs(state.lastSuccessfulSyncAt)),
                  _syncRow('Last Attempt', _formatTs(state.syncHealth?.lastSyncAt)),
                  _syncRow('Data Age', state.dataAgeLabel),
                  _syncRow('Auto Sync', 'Every ${AppConstants.syncIntervalDays} days'),
                  _syncRow('App Version', state.appVersion),
                  _syncRow(
                    'Last Synced Version',
                    state.lastSyncedAppVersion ?? '—',
                  ),
                  _syncRow('Future Sessions', '${state.futureSessionCount}'),
                ],
              ),
            ),
          ),
          ListTile(
            title: const Text('Manual Sync'),
            subtitle: Text(state.syncMessage ?? 'Pull latest schedules from ottawa.ca'),
            trailing: state.isSyncing
                ? const CircularProgressIndicator()
                : IconButton(
                    icon: const Icon(Icons.sync),
                    onPressed: state.manualSync,
                  ),
          ),
          const Divider(),
          const ListTile(
            title: Text('Map & Navigation'),
            subtitle: Text('Offline tiles and preferred navigation app'),
          ),
          ListTile(
            title: const Text('Cached map tiles'),
            subtitle: Text(
              _cacheInfo == null
                  ? 'Loading…'
                  : '${_cacheInfo!.tileCount} tiles · ${_cacheInfo!.sizeLabel}',
            ),
            trailing: _cachingTiles
                ? SizedBox(
                    width: 48,
                    child: CircularProgressIndicator(value: _cacheProgress),
                  )
                : IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: 'Cache Ottawa map',
                    onPressed: _cachingTiles ? null : _downloadOttawaTiles,
                  ),
          ),
          if (_cachingTiles)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(value: _cacheProgress),
            ),
          ListTile(
            title: const Text('Preferred navigation app'),
            subtitle: Text(_preferredNavApp ?? 'Not set'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await getIt<NavigationService>().showMapPickerForSettings(context);
              await _loadMapSettings();
            },
          ),
          ListTile(
            title: const Text('Clear tile cache'),
            subtitle: const Text('Remove downloaded map tiles'),
            onTap: () async {
              await getIt<MapTileCacheService>().clearCache();
              await _loadMapSettings();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Map tile cache cleared')),
                );
              }
            },
          ),
          const Divider(),
          const ListTile(title: Text('Notifications')),
          const _NotificationToggle(
            title: 'Favorite pool swims',
            settingKey: 'notify_favorites',
          ),
          const _NotificationToggle(
            title: 'Nearby swims starting soon',
            settingKey: 'notify_nearby',
          ),
          const _NotificationToggle(
            title: 'Daily swim reminder',
            settingKey: 'notify_daily_reminder',
          ),
          const Divider(),
          ListTile(
            title: const Text('Diagnostics'),
            subtitle: const Text('Schedule health and sync status'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, '/diagnostics'),
          ),
        ],
      ),
    );
  }

  Widget _syncRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 150, child: Text(label)),
            Expanded(
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );

  String _formatTs(DateTime? dt) =>
      dt == null ? 'Never' : DateFormat.yMMMd().add_jm().format(dt);
}

class _NotificationToggle extends StatefulWidget {
  const _NotificationToggle({required this.title, required this.settingKey});

  final String title;
  final String settingKey;

  @override
  State<_NotificationToggle> createState() => _NotificationToggleState();
}

class _NotificationToggleState extends State<_NotificationToggle> {
  bool _value = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final value = await state.getNotificationSetting(widget.settingKey);
    if (mounted) setState(() => _value = value);
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(widget.title),
      value: _value,
      onChanged: (v) async {
        setState(() => _value = v);
        await context.read<AppState>().setNotificationSetting(widget.settingKey, v);
      },
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) return iterator.current;
    return null;
  }
}
