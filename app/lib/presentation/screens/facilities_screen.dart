import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/ottawa_time.dart';
import '../../data/services/facility_browse_helper.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/facility_type.dart';
import '../../domain/entities/schedule_entry.dart';
import '../providers/app_state.dart';
import '../widgets/schedule_session_card.dart';
import 'facility_screen.dart';

enum FacilityBrowseTab { today, tomorrow, upcoming }

class FacilitiesScreen extends StatefulWidget {
  const FacilitiesScreen({super.key});

  @override
  State<FacilitiesScreen> createState() => _FacilitiesScreenState();
}

class _FacilitiesScreenState extends State<FacilitiesScreen> {
  Facility? _selected;
  FacilityBrowseTab _tab = FacilityBrowseTab.today;
  List<ScheduleEntry> _swims = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initSelection());
  }

  void _initSelection() {
    final filtered = context.read<AppState>().filteredFacilities;
    if (filtered.isNotEmpty) {
      setState(() => _selected = filtered.first);
      _loadSwims();
    }
  }

  Future<void> _loadSwims() async {
    final facility = _selected;
    if (facility == null) return;

    if (!facility.hasSwimSchedule) {
      setState(() {
        _swims = [];
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);

    final state = context.read<AppState>();
    final today = OttawaTime.todayDate();
    final tomorrow = OttawaTime.formatDate(
      DateTime.now().add(const Duration(days: 1)),
    );

    List<ScheduleEntry> swims;
    switch (_tab) {
      case FacilityBrowseTab.today:
        swims = await state.scheduleForFacilityOnDate(facility.id, today);
      case FacilityBrowseTab.tomorrow:
        swims = await state.scheduleForFacilityOnDate(facility.id, tomorrow);
      case FacilityBrowseTab.upcoming:
        swims = await state.upcomingForFacility(facility.id);
    }

    if (mounted) {
      setState(() {
        _swims = swims;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final filtered = state.filteredFacilities;
    final counts = state.facilityBrowseCounts;

    if (_selected == null && filtered.isNotEmpty) {
      _selected = filtered.first;
    } else if (_selected != null &&
        !filtered.any((f) => f.id == _selected!.id)) {
      _selected = filtered.isNotEmpty ? filtered.first : null;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Facilities'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh facility catalog',
            onPressed: state.isSyncing ? null : () => state.refreshFacilityAudit(),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Text(
              '${counts['visible']}/${counts['total']} facilities · '
              '${counts['indoor']} indoor · ${counts['outdoor']} outdoor',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  label: Text('Indoor (${counts['indoor']})'),
                  selected: state.facilityTypeFilter == FacilityType.indoorPool,
                  onSelected: (_) => state.setFacilityTypeFilter(
                    state.facilityTypeFilter == FacilityType.indoorPool
                        ? null
                        : FacilityType.indoorPool,
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('Outdoor (${counts['outdoor']})'),
                  selected:
                      state.facilityTypeFilter == FacilityType.outdoorPool,
                  onSelected: (_) => state.setFacilityTypeFilter(
                    state.facilityTypeFilter == FacilityType.outdoorPool
                        ? null
                        : FacilityType.outdoorPool,
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('Wave (${counts['wave']})'),
                  selected: state.facilityTypeFilter == FacilityType.wavePool,
                  onSelected: (_) => state.setFacilityTypeFilter(
                    state.facilityTypeFilter == FacilityType.wavePool
                        ? null
                        : FacilityType.wavePool,
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text('Wading (${counts['wading']})'),
                  selected: state.facilityTypeFilter == FacilityType.wadingPool,
                  onSelected: (_) => state.setFacilityTypeFilter(
                    state.facilityTypeFilter == FacilityType.wadingPool
                        ? null
                        : FacilityType.wadingPool,
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Has swim schedule'),
                  selected: state.scheduleModeFilter ==
                      FacilityScheduleMode.swimSchedule,
                  onSelected: (_) => state.setScheduleModeFilter(
                    state.scheduleModeFilter ==
                            FacilityScheduleMode.swimSchedule
                        ? null
                        : FacilityScheduleMode.swimSchedule,
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Open hours only'),
                  selected: state.scheduleModeFilter ==
                      FacilityScheduleMode.openHoursOnly,
                  onSelected: (_) => state.setScheduleModeFilter(
                    state.scheduleModeFilter ==
                            FacilityScheduleMode.openHoursOnly
                        ? null
                        : FacilityScheduleMode.openHoursOnly,
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: const Text('Seasonal only'),
                  selected: state.scheduleModeFilter ==
                      FacilityScheduleMode.seasonalOnly,
                  onSelected: (_) => state.setScheduleModeFilter(
                    state.scheduleModeFilter ==
                            FacilityScheduleMode.seasonalOnly
                        ? null
                        : FacilityScheduleMode.seasonalOnly,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: filtered.isEmpty
                ? const Center(child: Text('No facilities match filters.'))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final facility = filtered[index];
                      final status = state.browseStatusFor(facility);
                      final sessionCount =
                          state.facilitySessionCounts[facility.id] ?? 0;
                      final selected = _selected?.id == facility.id;

                      return ListTile(
                        selected: selected,
                        title: Text(facility.name),
                        subtitle: Text(
                          FacilityBrowseHelper.subtitleFor(
                            facility: facility,
                            status: status,
                            sessionCount: sessionCount,
                          ),
                        ),
                        trailing: _statusChip(context, status),
                        onTap: () {
                          setState(() => _selected = facility);
                          _loadSwims();
                        },
                        onLongPress: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                FacilityScreen(facilityId: facility.id),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_selected != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _selected!.hasSwimSchedule
                    ? 'Swim schedule — ${_selected!.name}'
                    : '${_selected!.name} — ${_selected!.scheduleMode.label}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            if (!_selected!.hasSwimSchedule)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  _selected!.isSeasonal
                      ? 'Seasonal outdoor facility. Check ottawa.ca for opening dates and hours.'
                      : 'This facility uses open hours rather than swim session tables.',
                ),
              ),
            if (_selected!.hasSwimSchedule)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SegmentedButton<FacilityBrowseTab>(
                  segments: const [
                    ButtonSegment(
                      value: FacilityBrowseTab.today,
                      label: Text('Today'),
                    ),
                    ButtonSegment(
                      value: FacilityBrowseTab.tomorrow,
                      label: Text('Tomorrow'),
                    ),
                    ButtonSegment(
                      value: FacilityBrowseTab.upcoming,
                      label: Text('Upcoming'),
                    ),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (s) {
                    setState(() => _tab = s.first);
                    _loadSwims();
                  },
                ),
              ),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              flex: 3,
              child: !_selected!.hasSwimSchedule
                  ? const SizedBox.shrink()
                  : _swims.isEmpty
                      ? const Center(child: Text('No swims for this period.'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _swims.length,
                          itemBuilder: (context, index) {
                            final swim = _swims[index];
                            return ScheduleSessionCard(
                              entry: swim,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FacilityScreen(
                                    facilityId: swim.facilityId,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, FacilityBrowseStatus status) {
    final color = switch (status) {
      FacilityBrowseStatus.open => Colors.green,
      FacilityBrowseStatus.seasonal => Colors.orange,
      FacilityBrowseStatus.stale => Colors.amber,
      FacilityBrowseStatus.noSchedule => Colors.grey,
      FacilityBrowseStatus.closed => Colors.red,
    };
    return Chip(
      label: Text(status.label, style: const TextStyle(fontSize: 11)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}
