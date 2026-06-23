import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/ottawa_time.dart';
import '../../domain/entities/schedule_entry.dart';
import '../providers/app_state.dart';
import '../widgets/schedule_session_card.dart';
import '../widgets/calendar_export_sheet.dart';
import '../widgets/save_swim_sheet.dart';
import '../widgets/swim_filter_chips.dart';
import 'facility_screen.dart';

enum FindSwimMode { activeAt, afterTime }

class FindSwimScreen extends StatefulWidget {
  const FindSwimScreen({super.key});

  @override
  State<FindSwimScreen> createState() => _FindSwimScreenState();
}

class _FindSwimScreenState extends State<FindSwimScreen> {
  FindSwimDatePreset _datePreset = FindSwimDatePreset.today;
  DateTime? _customStart;
  DateTime? _customEnd;
  TimeOfDay _selectedTime = TimeOfDay.now();
  FindSwimMode _mode = FindSwimMode.activeAt;
  final Set<String> _typeFilters = {};
  String? _facilityId;
  double? _maxDistanceKm;
  List<ScheduleEntry> _results = [];
  bool _searched = false;
  bool _loading = false;

  (String start, String end) _dateRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_datePreset) {
      case FindSwimDatePreset.today:
        final d = OttawaTime.formatDate(today);
        return (d, d);
      case FindSwimDatePreset.tomorrow:
        final t = today.add(const Duration(days: 1));
        final d = OttawaTime.formatDate(t);
        return (d, d);
      case FindSwimDatePreset.weekend:
        final daysUntilSat = (DateTime.saturday - today.weekday + 7) % 7;
        final sat = today.add(Duration(days: daysUntilSat));
        final sun = sat.add(const Duration(days: 1));
        return (OttawaTime.formatDate(sat), OttawaTime.formatDate(sun));
      case FindSwimDatePreset.next7Days:
        return (
          OttawaTime.formatDate(today),
          OttawaTime.formatDate(today.add(const Duration(days: 6))),
        );
      case FindSwimDatePreset.custom:
        final start = _customStart ?? today;
        final end = _customEnd ?? start;
        return (OttawaTime.formatDate(start), OttawaTime.formatDate(end));
    }
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _searched = true;
    });

    final state = context.read<AppState>();
    final time =
        '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';
    final (startDate, endDate) = _dateRange();
    final categories =
        _typeFilters.isEmpty ? null : _typeFilters.toList();

    final results = _mode == FindSwimMode.activeAt
        ? await state.findSwimsActiveAt(
            time,
            date: startDate,
            endDate: startDate == endDate ? null : endDate,
            categories: categories,
            facilityId: _facilityId,
            maxDistanceKm: _maxDistanceKm,
          )
        : await state.findSwimsAfter(
            time,
            date: startDate,
            endDate: endDate,
            categories: categories,
            facilityId: _facilityId,
            maxDistanceKm: _maxDistanceKm,
            nextAcrossDays: startDate == endDate,
          );

    setState(() {
      _results = results;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final (startDate, endDate) = _dateRange();

    return Scaffold(
      appBar: AppBar(title: const Text('Find Swim')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('When', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: FindSwimDatePreset.values.map((preset) {
              return ChoiceChip(
                label: Text(_presetLabel(preset)),
                selected: _datePreset == preset,
                onSelected: (_) async {
                  if (preset == FindSwimDatePreset.custom) {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 120)),
                    );
                    if (range != null) {
                      setState(() {
                        _datePreset = preset;
                        _customStart = range.start;
                        _customEnd = range.end;
                      });
                    }
                  } else {
                    setState(() => _datePreset = preset);
                  }
                },
              );
            }).toList(),
          ),
          if (_datePreset == FindSwimDatePreset.custom &&
              _customStart != null &&
              _customEnd != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${OttawaTime.formatDate(_customStart!)} → '
                '${OttawaTime.formatDate(_customEnd!)}',
              ),
            ),
          const SizedBox(height: 12),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).dividerColor),
            ),
            leading: const Icon(Icons.access_time),
            title: Text(_selectedTime.format(context)),
            subtitle: Text(
              _mode == FindSwimMode.activeAt
                  ? 'Active at this time'
                  : 'Starts after this time',
            ),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _selectedTime,
              );
              if (picked != null) setState(() => _selectedTime = picked);
            },
          ),
          const SizedBox(height: 12),
          SwimTypeFilterChips(
            selected: _typeFilters,
            onChanged: (next) => setState(() {
              _typeFilters
                ..clear()
                ..addAll(next);
            }),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            initialValue: _facilityId,
            decoration: const InputDecoration(
              labelText: 'Facility (optional)',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('All facilities')),
              ...state.facilities.map(
                (f) => DropdownMenuItem(value: f.id, child: Text(f.name)),
              ),
            ],
            onChanged: (v) => setState(() => _facilityId = v),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<double?>(
            initialValue: _maxDistanceKm,
            decoration: const InputDecoration(
              labelText: 'Max distance (optional)',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('Any distance')),
              DropdownMenuItem(value: 5.0, child: Text('Within 5 km')),
              DropdownMenuItem(value: 10.0, child: Text('Within 10 km')),
              DropdownMenuItem(value: 20.0, child: Text('Within 20 km')),
            ],
            onChanged: (v) => setState(() => _maxDistanceKm = v),
          ),
          const SizedBox(height: 12),
          SegmentedButton<FindSwimMode>(
            segments: const [
              ButtonSegment(
                value: FindSwimMode.activeAt,
                label: Text('Active at time'),
                icon: Icon(Icons.pool),
              ),
              ButtonSegment(
                value: FindSwimMode.afterTime,
                label: Text('Starts after'),
                icon: Icon(Icons.arrow_forward),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loading ? null : _search,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: const Text('Search swims'),
          ),
          const SizedBox(height: 24),
          if (_searched && !_loading) ...[
            Text(
              '${_results.length} result(s) · $startDate'
              '${startDate != endDate ? ' → $endDate' : ''}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_results.isEmpty)
              const Text('No matching swims. Try another date/time or sync.')
            else
              ..._results.map(
                (swim) => ScheduleSessionCard(
                  entry: swim,
                  showFacility: true,
                  isStale: state.isFacilityStale(swim.facilityId),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          FacilityScreen(facilityId: swim.facilityId),
                    ),
                  ),
                  onSave: () => showSaveSwimSheet(
                    context,
                    entry: swim,
                    onSave: ({reminderMinutes, asRecurring = false}) =>
                        state.saveSwim(
                      swim,
                      reminderMinutes: reminderMinutes,
                      asRecurring: asRecurring,
                    ),
                  ),
                  onExport: swim.date != null
                      ? () => showCalendarExportSheet(context, entry: swim)
                      : null,
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _presetLabel(FindSwimDatePreset preset) => switch (preset) {
        FindSwimDatePreset.today => 'Today',
        FindSwimDatePreset.tomorrow => 'Tomorrow',
        FindSwimDatePreset.weekend => 'Weekend',
        FindSwimDatePreset.next7Days => 'Next 7 Days',
        FindSwimDatePreset.custom => 'Custom',
      };
}

enum FindSwimDatePreset {
  today,
  tomorrow,
  weekend,
  next7Days,
  custom,
}
