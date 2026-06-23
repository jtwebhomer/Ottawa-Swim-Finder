import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/ottawa_time.dart';
import '../../di/injection.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/usecases/swim_usecases.dart';
import '../providers/app_state.dart';
import '../widgets/navigation_launch_button.dart';
import '../widgets/schedule_session_card.dart';
import '../widgets/swim_session_presenter.dart';

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
    _load();
  }

  Future<void> _load() async {
    final facilityRepo = getIt<FacilityRepository>();
    final scheduleRepo = getIt<ScheduleRepository>();

    final facility = await facilityRepo.getFacilityById(widget.facilityId);
    final todayDate = OttawaTime.todayDate();
    final schedules = SwimSessionPresenter.sorted(
      await scheduleRepo.getSchedulesForFacility(widget.facilityId, date: todayDate),
    );

    final time = OttawaTime.nowTime();
    final concurrent = schedules
        .where((s) => OttawaTime.isActiveAt(start: s.startTime, end: s.endTime, time: time))
        .toList();

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

    final state = context.watch<AppState>();
    final now = OttawaTime.nowTime();
    final active = SwimSessionPresenter.activeNow(_todaySchedules, nowTime: now);
    final next = SwimSessionPresenter.nextUpcoming(_todaySchedules, nowTime: now);
    final remaining = _todaySchedules
        .where((s) => OttawaTime.isRemainingToday(end: s.endTime, time: now))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(facility.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await context.read<AppState>().refreshAll();
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
          const SizedBox(height: 16),
          Row(
            children: [
              Chip(label: Text('Occupancy: $_occupancy')),
              const Spacer(),
              if (facility.latitude != null && facility.longitude != null)
                NavigationLaunchButton(
                  latitude: facility.latitude!,
                  longitude: facility.longitude!,
                  title: facility.name,
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
          if (remaining.isEmpty && _todaySchedules.isEmpty)
            const Text('No swims scheduled for today')
          else if (remaining.isEmpty)
            const Text('No swims remaining today')
          else
            ...remaining.map(
              (s) => ScheduleSessionCard(
                entry: s,
                highlight: s.id == active?.id || s.id == next?.id,
              ),
            ),
        ],
      ),
    );
  }
}
