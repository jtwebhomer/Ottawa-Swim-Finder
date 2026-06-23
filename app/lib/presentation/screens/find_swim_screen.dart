import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/ottawa_time.dart';
import '../../domain/entities/schedule_entry.dart';
import '../providers/app_state.dart';
import '../widgets/schedule_session_card.dart';
import 'facility_screen.dart';

enum FindSwimMode { activeAt, afterTime }

class FindSwimScreen extends StatefulWidget {
  const FindSwimScreen({super.key});

  @override
  State<FindSwimScreen> createState() => _FindSwimScreenState();
}

class _FindSwimScreenState extends State<FindSwimScreen> {
  TimeOfDay _selectedTime = TimeOfDay.now();
  FindSwimMode _mode = FindSwimMode.activeAt;
  List<ScheduleEntry> _results = [];
  bool _searched = false;
  bool _loading = false;

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _searched = true;
    });

    final state = context.read<AppState>();
    final time =
        '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';

    final results = _mode == FindSwimMode.activeAt
        ? await state.findSwimsActiveAt(time)
        : await state.findSwimsAfter(time);

    setState(() {
      _results = results;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find a Swim at…')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Where can I swim tonight?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Pick a time to see pools with sessions active then, or the earliest swim after that time.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Theme.of(context).dividerColor),
            ),
            leading: const Icon(Icons.access_time),
            title: Text(_selectedTime.format(context)),
            subtitle: const Text('Tap to change time'),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: _selectedTime,
              );
              if (picked != null) setState(() => _selectedTime = picked);
            },
          ),
          const SizedBox(height: 12),
          SegmentedButton<FindSwimMode>(
            segments: const [
              ButtonSegment(
                value: FindSwimMode.activeAt,
                label: Text('Swimming at this time'),
                icon: Icon(Icons.pool),
              ),
              ButtonSegment(
                value: FindSwimMode.afterTime,
                label: Text('Earliest after'),
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
            label: Text(_mode == FindSwimMode.activeAt
                ? 'Find pools swimming at ${_selectedTime.format(context)}'
                : 'Find earliest swim after ${_selectedTime.format(context)}'),
          ),
          const SizedBox(height: 24),
          if (_searched && !_loading) ...[
            Text(
              '${_results.length} result(s) · ${OttawaTime.todayDate()}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_results.isEmpty)
              const Text('No matching swims. Try a different time or sync schedules.')
            else
              ..._results.map(
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
        ],
      ),
    );
  }
}
