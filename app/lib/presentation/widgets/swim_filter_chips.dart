import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../providers/app_state.dart';

class SwimQuickFilterChips extends StatelessWidget {
  const SwimQuickFilterChips({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final QuickFilter? selected;
  final ValueChanged<QuickFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final filter in QuickFilter.values)
          FilterChip(
            label: Text(_label(filter)),
            selected: selected == filter,
            onSelected: (_) => onSelected(filter),
          ),
      ],
    );
  }

  String _label(QuickFilter filter) => switch (filter) {
        QuickFilter.swimmingNow => 'Now',
        QuickFilter.withinOneHour => 'Within 1 Hour',
        QuickFilter.tonight => 'Tonight',
        QuickFilter.tomorrow => 'Tomorrow',
        QuickFilter.thisWeekend => 'Weekend',
      };
}

class SwimTypeFilterChips extends StatelessWidget {
  const SwimTypeFilterChips({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  static const _filterTypes = [
    SwimCategories.generalSwim,
    SwimCategories.laneSwim,
    SwimCategories.familySwim,
    SwimCategories.parentTot,
    SwimCategories.aquafit,
    SwimCategories.adultSwim,
    SwimCategories.womensSwim,
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final type in _filterTypes)
          FilterChip(
            label: Text(SwimCategories.filterLabels[type] ?? type),
            selected: selected.contains(type),
            onSelected: (on) {
              final next = Set<String>.from(selected);
              if (on) {
                next.add(type);
              } else {
                next.remove(type);
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}
