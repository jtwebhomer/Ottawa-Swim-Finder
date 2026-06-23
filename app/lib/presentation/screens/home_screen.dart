import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../providers/app_state.dart';
import 'facility_screen.dart';

class SwimmingNowScreen extends StatelessWidget {
  const SwimmingNowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Swimming Right Now'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: state.refreshAll),
        ],
      ),
      body: state.activeSwims.isEmpty
          ? const Center(
              child: Text('No active swim sessions across Ottawa right now'),
            )
          : ListView.builder(
              itemCount: state.activeSwims.length,
              itemBuilder: (context, index) {
                final swim = state.activeSwims[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Colors.green,
                      child: Icon(Icons.pool, color: Colors.white),
                    ),
                    title: Text(swim.facilityName ?? swim.facilityId),
                    subtitle: Text(
                      '${SwimCategories.labelFor(swim.category)} · ends ${swim.endTime}',
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FacilityScreen(facilityId: swim.facilityId),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class TimelineScreen extends StatefulWidget {
  const TimelineScreen({super.key});

  @override
  State<TimelineScreen> createState() => _TimelineScreenState();
}

class _TimelineScreenState extends State<TimelineScreen> {
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('City Timeline')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));
                    state.loadTimeline(_selectedDate);
                  },
                ),
                Expanded(
                  child: Text(
                    '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
                    state.loadTimeline(_selectedDate);
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: state.timeline.length,
              itemBuilder: (context, index) {
                final swim = state.timeline[index];
                return ListTile(
                  leading: Text(swim.startTime, style: const TextStyle(fontWeight: FontWeight.bold)),
                  title: Text(swim.facilityName ?? swim.facilityId),
                  subtitle: Text(
                    '${SwimCategories.labelFor(swim.category)} · ${swim.startTime}–${swim.endTime}',
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Ottawa Swim Finder')),
      body: RefreshIndicator(
        onRefresh: state.refreshAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (state.isLoading)
              const LinearProgressIndicator()
            else
              Text(
                '${state.facilities.length} pools · ${state.activeSwims.length} swimming now',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            const SizedBox(height: 16),
            _NearestCard(
              title: 'Nearest Active Swim',
              entry: state.nearestHighlights['active'],
            ),
            _NearestCard(
              title: 'Nearest Lane Swim',
              entry: state.nearestHighlights['lane'],
            ),
            _NearestCard(
              title: 'Nearest Public Swim',
              entry: state.nearestHighlights['public'],
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.pushNamed(context, '/find-swim'),
              icon: const Icon(Icons.schedule),
              label: const Text('Find a Swim at…'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SwimmingNowScreen()),
              ),
              icon: const Icon(Icons.waves),
              label: const Text('Swimming Right Now'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TimelineScreen()),
              ),
              icon: const Icon(Icons.timeline),
              label: const Text('City Timeline'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NearestCard extends StatelessWidget {
  const _NearestCard({required this.title, required this.entry});

  final String title;
  final dynamic entry;

  @override
  Widget build(BuildContext context) {
    if (entry == null) {
      return Card(
        child: ListTile(title: Text(title), subtitle: const Text('None found nearby')),
      );
    }

    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: Text(
          '${entry.facilityName} · ${entry.startTime}–${entry.endTime}'
          '${entry.distanceKm != null ? ' (${entry.distanceKm!.toStringAsFixed(1)} km)' : ''}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FacilityScreen(facilityId: entry.facilityId),
          ),
        ),
      ),
    );
  }
}
