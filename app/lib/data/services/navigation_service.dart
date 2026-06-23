import 'package:flutter/material.dart';
import 'package:map_launcher/map_launcher.dart';

import '../../domain/repositories/repositories.dart';

class NavigationService {
  NavigationService(this._settingsRepo);

  static const preferredNavAppKey = 'preferred_nav_app';

  final SettingsRepository _settingsRepo;

  Future<List<AvailableMap>> getInstalledMaps() => MapLauncher.installedMaps;

  Future<String?> getPreferredMapType() => _settingsRepo.getString(preferredNavAppKey);

  Future<void> setPreferredMapType(String mapTypeName) =>
      _settingsRepo.setString(preferredNavAppKey, mapTypeName);

  Future<void> clearPreferredMapType() =>
      _settingsRepo.setString(preferredNavAppKey, '');

  Future<AvailableMap?> _findPreferredMap(List<AvailableMap> maps) async {
    final preferred = await getPreferredMapType();
    if (preferred == null || preferred.isEmpty) return null;
    for (final map in maps) {
      if (map.mapType.name == preferred) return map;
    }
    return null;
  }

  Future<void> showDirections({
    required double latitude,
    required double longitude,
    required String title,
    double? originLat,
    double? originLng,
    BuildContext? context,
  }) async {
    final maps = await getInstalledMaps();
    if (maps.isEmpty) {
      throw NavigationException('No navigation apps installed on this device.');
    }

    var selected = await _findPreferredMap(maps);

    if (selected == null && context != null) {
      if (!context.mounted) return;
      selected = await _showMapPicker(context, maps, rememberChoice: true);
    }
    selected ??= maps.first;

    await selected.showDirections(
      destination: Coords(latitude, longitude),
      destinationTitle: title,
      origin: originLat != null && originLng != null
          ? Coords(originLat, originLng)
          : null,
      directionsMode: DirectionsMode.driving,
    );
  }

  Future<AvailableMap?> _showMapPicker(
    BuildContext context,
    List<AvailableMap> maps, {
    bool rememberChoice = false,
  }) async {
    return showModalBottomSheet<AvailableMap>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Open directions in…',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ...maps.map(
              (map) => ListTile(
                leading: const Icon(Icons.map),
                title: Text(map.mapName),
                onTap: () async {
                  if (rememberChoice) {
                    await setPreferredMapType(map.mapType.name);
                  }
                  if (ctx.mounted) Navigator.pop(ctx, map);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> showMapPickerForSettings(BuildContext context) async {
    final maps = await getInstalledMaps();
    if (maps.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No navigation apps found')),
      );
      return;
    }

    if (!context.mounted) return;
    final selected = await _showMapPicker(context, maps, rememberChoice: true);
    if (selected != null) {
      await setPreferredMapType(selected.mapType.name);
    }
  }
}

class NavigationException implements Exception {
  NavigationException(this.message);
  final String message;

  @override
  String toString() => message;
}
