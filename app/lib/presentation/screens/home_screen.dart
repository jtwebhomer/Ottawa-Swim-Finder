import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/services/habit_detection_service.dart';
import '../../data/services/swim_query_service.dart';
import '../../domain/entities/schedule_entry.dart';
import '../providers/app_state.dart';
import '../widgets/data_freshness_card.dart';
import '../widgets/home_empty_state.dart';
import '../widgets/home_swim_card.dart';
import '../widgets/swim_session_presenter.dart';
import '../widgets/sync_status_indicator.dart';
import 'facilities_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _tomorrowExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, HomeSwimSections>(
      selector: (_, state) => state.homeSections,
      builder: (context, sections, _) {
        final hints = sections.habitHints;
        final allEmpty = sections.isEmpty;
        final state = context.read<AppState>();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Swims'),
            actions: [
              IconButton(
                icon: const Icon(Icons.apartment_outlined),
                tooltip: 'Browse pools',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FacilitiesScreen()),
                ),
              ),
              const SyncStatusIndicator(),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () => state.manualSync(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                DataFreshnessCard(state: state),
                if (allEmpty)
                  const HomeAllEmptyState()
                else ...[
                  _section(
                    context,
                    title: 'Swimming Now',
                    swims: sections.swimmingNow,
                    habitHints: hints,
                    emptyTitle: 'No swims happening right now',
                    emptySubtitle: 'Check Starting Soon or Tonight below.',
                    highlight: true,
                  ),
                  _section(
                    context,
                    title: 'Starting Soon',
                    swims: sections.startingSoon,
                    habitHints: hints,
                    emptyTitle: 'Nothing starting in the next few hours',
                    emptySubtitle: 'Tonight and Tomorrow may still have options.',
                  ),
                  _section(
                    context,
                    title: 'Tonight',
                    swims: sections.tonight,
                    habitHints: hints,
                    emptyTitle: 'No evening swims scheduled',
                    emptySubtitle: 'Try Tomorrow for the next available times.',
                  ),
                  _tomorrowSection(sections.tomorrow, hints),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required List<ScheduleEntry> swims,
    required Map<String, String> habitHints,
    required String emptyTitle,
    String? emptySubtitle,
    bool highlight = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        if (swims.isEmpty)
          HomeEmptyState(title: emptyTitle, subtitle: emptySubtitle)
        else
          ...swims.take(6).map(
                (swim) => HomeSwimCard(
                  entry: swim,
                  habitHint: habitHints[HabitDetectionService.entryKey(swim)],
                  highlight: highlight &&
                      SwimSessionPresenter.statusFor(swim).status ==
                          SwimSessionStatus.active,
                ),
              ),
      ],
    );
  }

  Widget _tomorrowSection(
    List<ScheduleEntry> swims,
    Map<String, String> habitHints,
  ) {
    final theme = Theme.of(context);
    final count = swims.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Material(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _tomorrowExpanded = !_tomorrowExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tomorrow',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          count == 0
                              ? 'No swims scheduled yet'
                              : '$count swim${count == 1 ? '' : 's'} scheduled',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Icon(_tomorrowExpanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
        ),
        if (_tomorrowExpanded) ...[
          if (count == 0)
            const HomeEmptyState(
              title: 'Nothing on the calendar for tomorrow yet',
              subtitle: 'Schedules update automatically in the background.',
              icon: Icons.calendar_today_outlined,
            )
          else
            ...swims.take(8).map(
                  (swim) => HomeSwimCard(
                    entry: swim,
                    habitHint: habitHints[HabitDetectionService.entryKey(swim)],
                  ),
                ),
        ],
      ],
    );
  }
}
