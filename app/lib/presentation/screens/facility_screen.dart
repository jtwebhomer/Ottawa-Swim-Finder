import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/ottawa_time.dart';
import '../../data/services/facility_interaction_service.dart';
import '../../data/services/facility_availability_presenter.dart';
import '../../di/injection.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/facility_type.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/usecases/swim_usecases.dart';
import '../providers/app_state.dart';
import '../widgets/navigation_launch_button.dart';
import '../widgets/schedule_session_card.dart';
import '../widgets/swim_session_presenter.dart';
import 'facility_schedule_screen.dart';

class FacilityScreen extends StatefulWidget {
  const FacilityScreen({super.key, required this.facilityId});

  final String facilityId;

  @override
  State<FacilityScreen> createState() => _FacilityScreenState();
}

class _FacilityScreenState extends State<FacilityScreen> {
  Facility? _facility;
  List<ScheduleEntry> _todaySchedules = [];
  String _occupancy = 'Unknown';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(getIt<FacilityInteractionService>().recordView(widget.facilityId));
    _load();
  }

  Future<void> _load() async {
    final facilityRepo = getIt<FacilityRepository>();
    final scheduleRepo = getIt<ScheduleRepository>();

    final facility = await facilityRepo.getFacilityById(widget.facilityId);
    final todayDate = OttawaTime.todayDate();
    final schedules = SwimSessionPresenter.sorted(
      await scheduleRepo.getTimelineForDate(todayDate, facilityId: widget.facilityId),
    );

    final time = OttawaTime.nowTime();
    final concurrent = schedules
        .where((s) => OttawaTime.isActiveAt(start: s.startTime, end: s.endTime, time: time))
        .toList();

    if (!mounted) return;
    setState(() {
      _facility = facility;
      _todaySchedules = schedules;
      _occupancy = OccupancyEstimator.estimate(concurrent);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final facility = _facility;
    if (facility == null) {
      return const Scaffold(body: Center(child: Text('Facility not found')));
    }

    final state = context.read<AppState>();
    final now = OttawaTime.nowTime();
    final active = SwimSessionPresenter.activeNow(_todaySchedules, nowTime: now);
    final next = SwimSessionPresenter.nextUpcoming(_todaySchedules, nowTime: now);

    return Scaffold(
      appBar: AppBar(
        title: Text(facility.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await state.refreshAll();
              await _load();
            },
          ),
          IconButton(
            icon: Icon(
              facility.isFavorite ? Icons.favorite : Icons.favorite_border,
              color: facility.isFavorite ? Colors.red : null,
            ),
            onPressed: () async {
              await state.toggleFavorite(facility);
              await _load();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(facility.address ?? '', style: Theme.of(context).textTheme.bodyLarge),
          if (facility.region != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Region: ${facility.region}'),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${facility.aquaticSettingLabel} · ${facility.facilityType.label} · ${facility.scheduleMode.label}',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FacilityScheduleScreen(facilityId: facility.id),
              ),
            ),
            icon: const Icon(Icons.calendar_month),
            label: Text(
              facility.usesSwimScheduleUi
                  ? 'View full schedule'
                  : 'View hours & status',
            ),
          ),
          const SizedBox(height: 16),
          if (!facility.usesSwimScheduleUi)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      FacilityAvailabilityPresenter.headline(facility),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(FacilityAvailabilityPresenter.detail(facility)),
                  ],
                ),
              ),
            ),
          if (facility.usesSwimScheduleUi) ...[
            Row(
              children: [
                Flexible(child: Chip(label: Text('Occupancy: $_occupancy'))),
                const SizedBox(width: 8),
                if (facility.latitude != null && facility.longitude != null)
                  NavigationLaunchButton(
                    latitude: facility.latitude!,
                    longitude: facility.longitude!,
                    title: facility.name,
                    facilityId: facility.id,
                  ),
              ],
            ),
            if (active != null) ...[
              const SizedBox(height: 16),
              Text('Now', style: Theme.of(context).textTheme.titleLarge),
              ScheduleSessionCard(entry: active, highlight: true),
            ],
            if (next != null && next.id != active?.id) ...[
              const SizedBox(height: 16),
              Text('Up Next', style: Theme.of(context).textTheme.titleLarge),
              ScheduleSessionCard(entry: next, highlight: true),
            ],
            const SizedBox(height: 16),
            Text('Today', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (_todaySchedules.isEmpty)
              const Text('No swims scheduled for today — try Tomorrow in full schedule.')
            else
              ..._todaySchedules.map(
                (s) => ScheduleSessionCard(
                  entry: s,
                  highlight: s.id == active?.id || s.id == next?.id,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
