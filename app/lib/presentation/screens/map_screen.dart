import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster_2/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../data/services/facility_availability_presenter.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/map_tile_cache_service.dart';
import '../../di/injection.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/facility_type.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/usecases/swim_usecases.dart';
import '../providers/app_state.dart';
import '../widgets/home_swim_card.dart';
import '../widgets/swim_filter_chips.dart';
import '../widgets/sync_status_indicator.dart';
import '../widgets/swim_session_presenter.dart';
import 'facility_schedule_screen.dart';
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
    final tileCache = getIt<MapTileCacheService>();

    return Selector<
        AppState,
        ({
          List<Facility> facilities,
          Map<String, PinStatus> pinStatuses,
          double? userLat,
          double? userLng,
          FacilityType? mapFacilityTypeFilter,
        })>(
      selector: (_, state) => (
        facilities: state.mapVisibleFacilities,
        pinStatuses: state.pinStatuses,
        userLat: state.userLat,
        userLng: state.userLng,
        mapFacilityTypeFilter: state.mapFacilityTypeFilter,
      ),
      builder: (context, data, _) {
        final mappableFacilities = data.facilities;

        final clusterMarkers = mappableFacilities.map((facility) {
          final status = data.pinStatuses[facility.id] ?? PinStatus.inactive;
          return Marker(
            point: LatLng(facility.latitude!, facility.longitude!),
            width: 120,
            height: 56,
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () => setState(() => _selectedFacility = facility),
              child: _FacilityPin(
                facility: facility,
                status: status,
                selected: _selectedFacility?.id == facility.id,
              ),
            ),
          );
        }).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Map'),
            actions: [
              if (data.userLat != null && data.userLng != null)
                IconButton(
                  icon: const Icon(Icons.my_location),
                  tooltip: 'Center on my location',
                  onPressed: () {
                    _mapController.move(
                      LatLng(data.userLat!, data.userLng!),
                      12,
                    );
                  },
                ),
              const SyncStatusIndicator(),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: AquaticFacilityTypeFilterChips(
                  selected: data.mapFacilityTypeFilter,
                  onChanged: context.read<AppState>().setMapFacilityTypeFilter,
                ),
              ),
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
                    if (data.userLat != null && data.userLng != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(data.userLat!, data.userLng!),
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
                  key: ValueKey(_selectedFacility!.id),
                  facility: _selectedFacility!,
                  status: data.pinStatuses[_selectedFacility!.id] ??
                      PinStatus.inactive,
                  onDismiss: () => setState(() => _selectedFacility = null),
                )
              else
                _MapLegend(facilityCount: mappableFacilities.length),
            ],
          ),
        );
      },
    );
  }
}

class _FacilityPin extends StatelessWidget {
  const _FacilityPin({
    required this.facility,
    required this.status,
    required this.selected,
  });

  final Facility facility;
  final PinStatus status;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final typeColor = AppTheme.pinColorForType(facility.facilityType);
    final color = switch (status) {
      PinStatus.active => AppTheme.pinActive,
      PinStatus.upcoming => AppTheme.pinUpcoming,
      PinStatus.inactive => typeColor.withValues(alpha: 0.85),
      PinStatus.seasonal => typeColor,
      PinStatus.openHours => typeColor,
    };
    final label = switch (status) {
      PinStatus.active => 'Now',
      PinStatus.upcoming => 'Soon',
      PinStatus.inactive => facility.dataModel.label,
      PinStatus.seasonal => 'Seasonal',
      PinStatus.openHours => 'Hours',
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? color : Theme.of(context).dividerColor,
              width: selected ? 2 : 1,
            ),
            boxShadow: const [
              BoxShadow(
                blurRadius: 4,
                color: Color(0x33000000),
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
          ),
        ),
        Icon(
          Icons.location_on,
          color: color,
          size: selected ? 44 : 36,
        ),
      ],
    );
  }
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
        child: Wrap(
          alignment: WrapAlignment.spaceAround,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            _LegendItem(color: AppTheme.pinIndoorPool, label: 'Indoor'),
            _LegendItem(color: AppTheme.pinWavePool, label: 'Wave'),
            _LegendItem(color: AppTheme.pinOutdoorPool, label: 'Outdoor'),
            _LegendItem(color: AppTheme.pinWadingPool, label: 'Wading'),
            _LegendItem(color: AppTheme.pinSplashPad, label: 'Splash'),
            Text('$facilityCount aquatic sites'),
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
        Icon(Icons.circle, color: color, size: 12),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _FacilityBottomSheet extends StatefulWidget {
  const _FacilityBottomSheet({
    super.key,
    required this.facility,
    required this.status,
    required this.onDismiss,
  });

  final Facility facility;
  final PinStatus status;
  final VoidCallback onDismiss;

  @override
  State<_FacilityBottomSheet> createState() => _FacilityBottomSheetState();
}

class _FacilityBottomSheetState extends State<_FacilityBottomSheet> {
  List<ScheduleEntry> _swims = [];
  bool _loading = true;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _FacilityBottomSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.facility.id != widget.facility.id) {
      setState(() {
        _loading = true;
        _swims = [];
      });
      _load();
    }
  }

  Future<void> _load() async {
    if (!widget.facility.usesSwimScheduleUi) {
      if (mounted) {
        setState(() {
          _swims = [];
          _loading = false;
        });
      }
      return;
    }

    final generation = ++_loadGeneration;
    final facilityId = widget.facility.id;

    final summary =
        await context.read<AppState>().facilitySwimSummary(facilityId);

    if (!mounted || generation != _loadGeneration || widget.facility.id != facilityId) {
      return;
    }

    var swims = SwimSessionPresenter.sorted(summary.todaySwims);
    if (swims.isEmpty && summary.tomorrowSwims.isNotEmpty) {
      swims = [...summary.tomorrowSwims];
    }

    setState(() {
      _swims = swims;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusLabel = switch (widget.status) {
      PinStatus.active => 'Swimming now',
      PinStatus.upcoming => 'Starting soon',
      PinStatus.inactive => widget.facility.dataModel.label,
      PinStatus.seasonal => 'Seasonal hours',
      PinStatus.openHours => 'Open hours only',
    };

    return Material(
      elevation: 12,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.48,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.facility.name,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (widget.facility.address != null)
                          Text(
                            widget.facility.address!,
                            style: theme.textTheme.bodySmall,
                          ),
                        Text(
                          statusLabel,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: switch (widget.status) {
                              PinStatus.active => AppTheme.pinActive,
                              PinStatus.upcoming => AppTheme.pinUpcoming,
                              PinStatus.inactive => theme.colorScheme.outline,
                              PinStatus.seasonal => theme.colorScheme.tertiary,
                              PinStatus.openHours => theme.colorScheme.outline,
                            },
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: widget.onDismiss,
                  ),
                ],
              ),
              if (_loading && widget.facility.usesSwimScheduleUi)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: Text('Loading swims…')),
                )
              else if (!widget.facility.usesSwimScheduleUi)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        FacilityAvailabilityPresenter.headline(widget.facility),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        FacilityAvailabilityPresenter.detail(widget.facility),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                )
              else if (_swims.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    FacilityAvailabilityPresenter.mapSheetMessage(widget.facility),
                  ),
                )
              else
                ..._swims.map(
                  (s) => HomeSwimCard(
                    entry: s,
                    compact: true,
                    facilityNameOverride: widget.facility.name,
                    facilityIdOverride: widget.facility.id,
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FacilityScheduleScreen(
                        facilityId: widget.facility.id,
                      ),
                    ),
                  ),
                  child: Text(
                    widget.facility.usesSwimScheduleUi
                        ? 'Full schedule'
                        : 'Facility details',
                  ),
                ),
              ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
