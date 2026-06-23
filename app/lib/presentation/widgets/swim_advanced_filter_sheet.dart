import 'package:flutter/material.dart';

import '../../domain/entities/facility_type.dart';
import '../../domain/repositories/repositories.dart';
import 'swim_filter_chips.dart';

/// Advanced swim search filters surfaced from Find Swim.
class SwimAdvancedFilters {
  const SwimAdvancedFilters({
    this.facilityType,
    this.swimTypes = const {},
    this.rawCategories = const {},
    this.distanceKm,
    this.timeOfDay,
  });

  final FacilityType? facilityType;
  final Set<String> swimTypes;
  final Set<String> rawCategories;
  final double? distanceKm;
  final SwimTimeOfDay? timeOfDay;

  SwimAdvancedFilters copyWith({
    FacilityType? facilityType,
    Set<String>? swimTypes,
    Set<String>? rawCategories,
    double? distanceKm,
    SwimTimeOfDay? timeOfDay,
  }) {
    return SwimAdvancedFilters(
      facilityType: facilityType ?? this.facilityType,
      swimTypes: swimTypes ?? this.swimTypes,
      rawCategories: rawCategories ?? this.rawCategories,
      distanceKm: distanceKm ?? this.distanceKm,
      timeOfDay: timeOfDay ?? this.timeOfDay,
    );
  }
}

enum SwimTimeOfDay { now, morning, afternoon, evening }

Future<SwimAdvancedFilters?> showSwimAdvancedFilterSheet(
  BuildContext context, {
  required SwimAdvancedFilters initial,
  List<CategoryInventoryRow> inventory = const [],
}) {
  return showModalBottomSheet<SwimAdvancedFilters>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _SwimAdvancedFilterSheet(
      initial: initial,
      inventory: inventory,
    ),
  );
}

class _SwimAdvancedFilterSheet extends StatefulWidget {
  const _SwimAdvancedFilterSheet({
    required this.initial,
    this.inventory = const [],
  });

  final SwimAdvancedFilters initial;
  final List<CategoryInventoryRow> inventory;

  @override
  State<_SwimAdvancedFilterSheet> createState() =>
      _SwimAdvancedFilterSheetState();
}

class _SwimAdvancedFilterSheetState extends State<_SwimAdvancedFilterSheet> {
  late FacilityType? _facilityType;
  late Set<String> _swimTypes;
  late Set<String> _rawCategories;
  late double? _distanceKm;
  late SwimTimeOfDay? _timeOfDay;

  @override
  void initState() {
    super.initState();
    _facilityType = widget.initial.facilityType;
    _swimTypes = Set<String>.from(widget.initial.swimTypes);
    _rawCategories = Set<String>.from(widget.initial.rawCategories);
    _distanceKm = widget.initial.distanceKm;
    _timeOfDay = widget.initial.timeOfDay;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Filters', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text('Facility type', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Any'),
                selected: _facilityType == null,
                onSelected: (_) => setState(() => _facilityType = null),
              ),
              for (final type in FacilityType.values)
                FilterChip(
                  label: Text(type.label),
                  selected: _facilityType == type,
                  onSelected: (_) => setState(() => _facilityType = type),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Swim type (grouped)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SwimTypeFilterChips(
            selected: _swimTypes,
            inventory: widget.inventory,
            onChanged: (v) => setState(() => _swimTypes = v),
          ),
          const SizedBox(height: 16),
          Text('Activity name (Ottawa)', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SwimRawCategoryFilterChips(
            selected: _rawCategories,
            inventory: widget.inventory,
            onChanged: (v) => setState(() => _rawCategories = v),
          ),
          const SizedBox(height: 16),
          Text('Distance', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final option in <(String, double?)>[
                ('Anywhere', null),
                ('5 km', 5),
                ('10 km', 10),
                ('20 km', 20),
              ])
                FilterChip(
                  label: Text(option.$1),
                  selected: _distanceKm == option.$2,
                  onSelected: (_) => setState(() => _distanceKm = option.$2),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Time of day', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: const Text('Any'),
                selected: _timeOfDay == null,
                onSelected: (_) => setState(() => _timeOfDay = null),
              ),
              for (final tod in SwimTimeOfDay.values)
                FilterChip(
                  label: Text(_timeLabel(tod)),
                  selected: _timeOfDay == tod,
                  onSelected: (_) => setState(() => _timeOfDay = tod),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              SwimAdvancedFilters(
                facilityType: _facilityType,
                swimTypes: _swimTypes,
                rawCategories: _rawCategories,
                distanceKm: _distanceKm,
                timeOfDay: _timeOfDay,
              ),
            ),
            child: const Text('Apply filters'),
          ),
        ],
      ),
    );
  }

  String _timeLabel(SwimTimeOfDay tod) => switch (tod) {
        SwimTimeOfDay.now => 'Now',
        SwimTimeOfDay.morning => 'Morning',
        SwimTimeOfDay.afternoon => 'Afternoon',
        SwimTimeOfDay.evening => 'Evening',
      };
}

extension SwimTimeOfDayRange on SwimTimeOfDay {
  (String start, String end) get timeRange => switch (this) {
        SwimTimeOfDay.now => ('00:00', '23:59'),
        SwimTimeOfDay.morning => ('05:00', '11:59'),
        SwimTimeOfDay.afternoon => ('12:00', '16:59'),
        SwimTimeOfDay.evening => ('17:00', '22:59'),
      };
}
