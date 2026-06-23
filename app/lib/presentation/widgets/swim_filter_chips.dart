import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/entities/facility_type.dart';
import '../../domain/repositories/repositories.dart';
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

/// Normalized swim-type filter chips — populated from database inventory when available.
class SwimTypeFilterChips extends StatelessWidget {
  const SwimTypeFilterChips({
    super.key,
    required this.selected,
    required this.onChanged,
    this.inventory = const [],
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final List<CategoryInventoryRow> inventory;

  @override
  Widget build(BuildContext context) {
    final normalizedTypes = _normalizedOptions();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final type in normalizedTypes)
          FilterChip(
            label: Text(SwimCategories.labelFor(type)),
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

  List<String> _normalizedOptions() {
    if (inventory.isEmpty) return SwimCategories.all;
    final fromDb = inventory.map((r) => r.normalizedCategory).toSet().toList()
      ..sort();
    return fromDb;
  }
}

/// Raw Ottawa activity name filter chips — generated from database inventory.
class SwimRawCategoryFilterChips extends StatelessWidget {
  const SwimRawCategoryFilterChips({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.inventory,
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final List<CategoryInventoryRow> inventory;

  @override
  Widget build(BuildContext context) {
    if (inventory.isEmpty) {
      return Text(
        'Activity names appear after schedules are loaded.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    final rawNames = inventory.map((r) => r.rawCategory).toSet().toList()..sort();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final raw in rawNames)
          FilterChip(
            label: Text(raw),
            selected: selected.contains(raw),
            onSelected: (on) {
              final next = Set<String>.from(selected);
              if (on) {
                next.add(raw);
              } else {
                next.remove(raw);
              }
              onChanged(next);
            },
          ),
      ],
    );
  }
}

/// Facility type filter chips for map and browse screens.
class AquaticFacilityTypeFilterChips extends StatelessWidget {
  const AquaticFacilityTypeFilterChips({
    super.key,
    required this.selected,
    required this.onChanged,
    this.showAllAquatic = true,
  });

  final FacilityType? selected;
  final ValueChanged<FacilityType?> onChanged;
  final bool showAllAquatic;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          if (showAllAquatic)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: const Text('All Aquatic'),
                selected: selected == null,
                onSelected: (_) => onChanged(null),
              ),
            ),
          for (final type in FacilityType.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(type.label),
                selected: selected == type,
                onSelected: (_) => onChanged(type),
              ),
            ),
        ],
      ),
    );
  }
}
