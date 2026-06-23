import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../providers/app_state.dart';
import 'facility_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _queryController = TextEditingController();
  final Set<String> _selectedCategories = {};
  DateTime? _selectedDate;
  double _maxDistance = 25;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return Scaffold(
      appBar: AppBar(title: const Text('Search Swims')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _queryController,
                  decoration: const InputDecoration(
                    labelText: 'Facility name',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: SwimCategories.all.map((cat) {
                    final selected = _selectedCategories.contains(cat);
                    return FilterChip(
                      label: Text(SwimCategories.filterLabels[cat]!),
                      selected: selected,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _selectedCategories.add(cat);
                          } else {
                            _selectedCategories.remove(cat);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: QuickFilter.values.map((qf) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          label: Text(_quickFilterLabel(qf)),
                          onPressed: () => state.search(quickFilter: qf),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text('Max distance: ${_maxDistance.round()} km'),
                    ),
                    Expanded(
                      child: Slider(
                        value: _maxDistance,
                        min: 1,
                        max: 50,
                        divisions: 49,
                        onChanged: (v) => setState(() => _maxDistance = v),
                      ),
                    ),
                  ],
                ),
                FilledButton(
                  onPressed: () {
                    final query = _queryController.text.toLowerCase();
                    final facility = state.facilities
                        .where((f) => f.name.toLowerCase().contains(query))
                        .firstOrNull;
                    state.search(
                      categories: _selectedCategories.isEmpty
                          ? null
                          : _selectedCategories.toList(),
                      facilityId: facility?.id,
                      date: _selectedDate,
                      maxDistanceKm: _maxDistance,
                    );
                  },
                  child: const Text('Search'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: state.searchResults.length,
              itemBuilder: (context, index) {
                final swim = state.searchResults[index];
                return ListTile(
                  leading: swim.distanceKm != null
                      ? CircleAvatar(child: Text('${swim.distanceKm!.toStringAsFixed(1)}'))
                      : const Icon(Icons.pool),
                  title: Text(swim.facilityName ?? swim.facilityId),
                  subtitle: Text(
                    '${SwimCategories.labelFor(swim.category)} · ${swim.date} ${swim.startTime}–${swim.endTime}',
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FacilityScreen(facilityId: swim.facilityId),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _quickFilterLabel(QuickFilter qf) => switch (qf) {
        QuickFilter.swimmingNow => 'Swimming Now',
        QuickFilter.withinOneHour => 'Within 1 Hour',
        QuickFilter.tonight => 'Tonight',
        QuickFilter.tomorrow => 'Tomorrow',
        QuickFilter.thisWeekend => 'This Weekend',
      };
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    if (iterator.moveNext()) return iterator.current;
    return null;
  }
}
