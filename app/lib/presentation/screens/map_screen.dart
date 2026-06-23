import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster_2/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/services/map_tile_cache_service.dart';
import '../../di/injection.dart';
import '../../domain/entities/facility.dart';
import '../../domain/usecases/swim_usecases.dart';
import '../providers/app_state.dart';
import '../widgets/navigation_launch_button.dart';
import 'facility_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  Facility? _selectedFacility;

  static const _ottawaCenter = LatLng(45.4215, -75.6972);

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tileCache = getIt<MapTileCacheService>();

    final mappableFacilities = state.facilities
        .where((f) => f.latitude != null && f.longitude != null)
        .toList();

    final clusterMarkers = mappableFacilities.map((facility) {
      final status = state.pinStatuses[facility.id] ?? PinStatus.inactive;
      final color = _pinColor(status);
      return Marker(
        point: LatLng(facility.latitude!, facility.longitude!),
        width: 40,
        height: 40,
        child: GestureDetector(
          onTap: () => setState(() => _selectedFacility = facility),
          child: Icon(Icons.location_on, color: color, size: 40),
        ),
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Pool Map'),
            const SizedBox(width: 4),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: 'Sync schedules',
              onPressed: state.isSyncing ? null : state.manualSync,
              icon: state.isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync, size: 22),
            ),
          ],
        ),
        actions: [
          if (state.userLat != null && state.userLng != null)
            IconButton(
              icon: const Icon(Icons.my_location),
              tooltip: 'Center on my location',
              onPressed: () {
                _mapController.move(
                  LatLng(state.userLat!, state.userLng!),
                  12,
                );
              },
            ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _ottawaCenter,
                      initialZoom: 11,
                      onTap: (_, __) => setState(() => _selectedFacility = null),
                    ),
                    children: [
                      tileCache.tileLayer,
                      if (state.userLat != null && state.userLng != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(state.userLat!, state.userLng!),
                              width: 36,
                              height: 36,
                              child: const Icon(
                                Icons.person_pin_circle,
                                color: Colors.blue,
                                size: 36,
                              ),
                            ),
                          ],
                        ),
                      MarkerClusterLayerWidget(
                        options: MarkerClusterLayerOptions(
                          maxClusterRadius: 60,
                          size: const Size(44, 44),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(48),
                          maxZoom: 14,
                          markers: clusterMarkers,
                          builder: (context, markers) {
                            return Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Center(
                                child: Text(
                                  markers.length.toString(),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onPrimary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                if (_selectedFacility != null)
                  _FacilityBottomSheet(
                    facility: _selectedFacility!,
                    status: state.pinStatuses[_selectedFacility!.id] ??
                        PinStatus.inactive,
                    onOpenDetails: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            FacilityScreen(facilityId: _selectedFacility!.id),
                      ),
                    ),
                    onDismiss: () => setState(() => _selectedFacility = null),
                  )
                else
                  _MapLegend(facilityCount: mappableFacilities.length),
              ],
            ),
    );
  }

  Color _pinColor(PinStatus status) => switch (status) {
        PinStatus.active => AppTheme.pinActive,
        PinStatus.upcoming => AppTheme.pinUpcoming,
        PinStatus.inactive => AppTheme.pinInactive,
      };
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.facilityCount});

  final int facilityCount;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _LegendItem(color: AppTheme.pinActive, label: 'Active now'),
            _LegendItem(color: AppTheme.pinUpcoming, label: 'Upcoming'),
            _LegendItem(color: AppTheme.pinInactive, label: 'No swims left'),
            Text('$facilityCount pools'),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.location_on, color: color, size: 20),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _FacilityBottomSheet extends StatelessWidget {
  const _FacilityBottomSheet({
    required this.facility,
    required this.status,
    required this.onOpenDetails,
    required this.onDismiss,
  });

  final Facility facility;
  final PinStatus status;
  final VoidCallback onOpenDetails;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (status) {
      PinStatus.active => 'Swimming now',
      PinStatus.upcoming => 'Upcoming swim today',
      PinStatus.inactive => 'No swims remaining today',
    };

    return Material(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(
              Icons.location_on,
              color: switch (status) {
                PinStatus.active => AppTheme.pinActive,
                PinStatus.upcoming => AppTheme.pinUpcoming,
                PinStatus.inactive => AppTheme.pinInactive,
              },
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(facility.name, style: Theme.of(context).textTheme.titleMedium),
                  Text(facility.address ?? ''),
                  Text(statusLabel, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (facility.latitude != null && facility.longitude != null)
              NavigationLaunchButton(
                latitude: facility.latitude!,
                longitude: facility.longitude!,
                title: facility.name,
                compact: true,
              ),
            TextButton(onPressed: onOpenDetails, child: const Text('Details')),
            IconButton(icon: const Icon(Icons.close), onPressed: onDismiss),
          ],
        ),
      ),
    );
  }
}
