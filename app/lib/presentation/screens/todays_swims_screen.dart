import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/ottawa_time.dart';
import '../../domain/entities/schedule_entry.dart';
import '../providers/app_state.dart';
import '../widgets/schedule_session_card.dart';
import '../widgets/swim_session_presenter.dart';
import 'facility_screen.dart';

class TodaysSwimsScreen extends StatefulWidget {
  const TodaysSwimsScreen({super.key});

  @override
  State<TodaysSwimsScreen> createState() => _TodaysSwimsScreenState();
}

class _TodaysSwimsScreenState extends State<TodaysSwimsScreen> {
  final Set<String> _typeFilters = {};
  String? _timeFilter;

  List<ScheduleEntry> get _filteredSwims {
    final state = context.read<AppState>();
    var swims = SwimSessionPresenter.sorted(state.todaysSwims);
    final now = OttawaTime.nowTime();

    if (_typeFilters.isNotEmpty) {
      swims = swims.where((s) => _typeFilters.contains(s.category)).toList();
    }

    swims = switch (_timeFilter) {
      'now' => swims
          .where((s) => OttawaTime.isActiveAt(
                start: s.startTime,
                end: s.endTime,
                time: now,
              ))
          .toList(),
      'hour' => swims
          .where((s) {
            final end = _addMinutes(now, 60);
            return s.startTime.compareTo(now) >= 0 &&
                s.startTime.compareTo(end) <= 0;
          })
          .toList(),
      'morning' ||
      'afternoon' ||
      'evening' =>
        swims.where((s) {
          final range = TimeOfDayFilter.rangeFor(_timeFilter!);
          if (range == null) return true;
          return s.startTime.compareTo(range.$1) >= 0 &&
              s.startTime.compareTo(range.$2) <= 0;
        }).toList(),
      _ => swims,
    };

    return swims;
  }

  String _addMinutes(String time, int minutes) {
    final parts = time.split(':');
    final total = int.parse(parts[0]) * 60 + int.parse(parts[1]) + minutes;
    final h = (total ~/ 60).clamp(0, 23);
    final m = total % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final swims = _filteredSwims;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Today's Swims"),
        actions: [
          IconButton(
            icon: const Icon(Icons.schedule),
            tooltip: 'Find swim at time',
            onPressed: () => Navigator.pushNamed(context, '/find-swim'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: state.refreshAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${state.todaysSwims.length} swims city-wide today',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text('Swim type', style: Theme.of(context).textTheme.labelLarge),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: SwimCategories.all.map((type) {
                final selected = _typeFilters.contains(type);
                return FilterChip(
                  label: Text(SwimCategories.filterLabels[type]!),
                  selected: selected,
                  onSelected: (v) => setState(() {
                    if (v) {
                      _typeFilters.add(type);
                    } else {
                      _typeFilters.remove(type);
                    }
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Text('Time', style: Theme.of(context).textTheme.labelLarge),
            Wrap(
              spacing: 8,
              children: [
                _timeChip('All', null),
                _timeChip('Swimming Now', 'now'),
                _timeChip('Within 1 Hour', 'hour'),
                _timeChip('Morning', 'morning'),
                _timeChip('Afternoon', 'afternoon'),
                _timeChip('Evening', 'evening'),
              ],
            ),
            const SizedBox(height: 16),
            if (swims.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: Text('No swims match these filters')),
              )
            else
              ...swims.map(
                (swim) => ScheduleSessionCard(
                  entry: swim,
                  showFacility: true,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FacilityScreen(facilityId: swim.facilityId),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _timeChip(String label, String? value) {
    final selected = _timeFilter == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _timeFilter = value),
    );
  }
}
