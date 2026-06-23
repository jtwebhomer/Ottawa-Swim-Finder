import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/ottawa_time.dart';
import '../providers/app_state.dart';
import '../widgets/schedule_session_card.dart';
import '../widgets/save_swim_sheet.dart';
import 'facility_screen.dart';

enum CalendarViewMode { day, week, month }

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarViewMode _mode = CalendarViewMode.day;
  DateTime _focusedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final state = context.read<AppState>();
      await state.loadCalendarDate(OttawaTime.todayDate());
      await state.loadCalendarMonth(_focusedMonth);
    });
  }

  Future<void> _reloadMonth(DateTime month) async {
    _focusedMonth = month;
    await context.read<AppState>().loadCalendarMonth(month);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final selected = DateTime.parse(state.calendarSelectedDate);
    final counts = state.calendarSwimCounts;
    final categories = state.calendarDominantCategories;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.skip_next),
            tooltip: 'Jump to next swim',
            onPressed: () async {
              final next = await state.nextAvailableSwim();
              if (next?.date != null && context.mounted) {
                await state.loadCalendarDate(next!.date!);
                if (_mode == CalendarViewMode.month) {
                  await _reloadMonth(DateTime.parse(next.date!));
                }
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<CalendarViewMode>(
              segments: const [
                ButtonSegment(value: CalendarViewMode.day, label: Text('Day')),
                ButtonSegment(value: CalendarViewMode.week, label: Text('Week')),
                ButtonSegment(value: CalendarViewMode.month, label: Text('Month')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
          ),
          if (_mode == CalendarViewMode.month)
            CalendarDatePicker(
              initialDate: selected,
              firstDate: DateTime.now().subtract(const Duration(days: 1)),
              lastDate: DateTime.now().add(const Duration(days: 120)),
              onDateChanged: (d) {
                context.read<AppState>().loadCalendarDate(OttawaTime.formatDate(d));
              },
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    final prev = selected.subtract(const Duration(days: 1));
                    context
                        .read<AppState>()
                        .loadCalendarDate(OttawaTime.formatDate(prev));
                  },
                ),
                Column(
                  children: [
                    Text(
                      state.calendarSelectedDate,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${counts[state.calendarSelectedDate] ?? 0} swims',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    final next = selected.add(const Duration(days: 1));
                    context
                        .read<AppState>()
                        .loadCalendarDate(OttawaTime.formatDate(next));
                  },
                ),
              ],
            ),
          if (_mode == CalendarViewMode.week)
            SizedBox(
              height: 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (var i = 0; i < 7; i++)
                    _DayChip(
                      date: selected.add(Duration(days: i - selected.weekday + 1)),
                      count: counts,
                      dominantCategory: categories,
                      selected: state.calendarSelectedDate,
                      onTap: (d) => context
                          .read<AppState>()
                          .loadCalendarDate(OttawaTime.formatDate(d)),
                    ),
                ],
              ),
            ),
          Expanded(
            child: state.calendarSwims.isEmpty
                ? Center(
                    child: Text(
                      'No swims on ${state.calendarSelectedDate}.\n'
                      '${state.futureSessionCount} future sessions in database.',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: state.calendarSwims.length,
                    itemBuilder: (context, index) {
                      final swim = state.calendarSwims[index];
                      return ScheduleSessionCard(
                        entry: swim,
                        showFacility: true,
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
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.date,
    required this.count,
    required this.dominantCategory,
    required this.selected,
    required this.onTap,
  });

  final DateTime date;
  final Map<String, int> count;
  final Map<String, String> dominantCategory;
  final String selected;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final key = OttawaTime.formatDate(date);
    final swimCount = count[key] ?? 0;
    final cat = dominantCategory[key];
    final isSelected = key == selected;
    final dotColor = cat != null ? _categoryColor(cat) : Colors.grey;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ActionChip(
        label: Text('${date.month}/${date.day} ($swimCount)'),
        avatar: swimCount > 0
            ? Icon(Icons.circle, size: 10, color: dotColor)
            : null,
        backgroundColor: isSelected
            ? Theme.of(context).colorScheme.primaryContainer
            : null,
        onPressed: () => onTap(date),
      ),
    );
  }

  Color _categoryColor(String category) => switch (category) {
        SwimCategories.laneSwim => Colors.blue,
        SwimCategories.generalSwim => Colors.teal,
        SwimCategories.familySwim => Colors.orange,
        SwimCategories.aquafit => Colors.purple,
        _ => Colors.grey,
      };
}
