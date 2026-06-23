import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/ottawa_time.dart';
import '../../domain/entities/schedule_entry.dart';
import '../providers/app_state.dart';
import '../widgets/calendar_export_sheet.dart';
import '../widgets/data_freshness_card.dart';
import '../widgets/schedule_session_card.dart';
import '../widgets/sync_progress_banner.dart';
import '../widgets/swim_filter_chips.dart';
import '../widgets/swim_session_presenter.dart';
import 'facilities_screen.dart';
import 'facility_screen.dart';
import 'tonight_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  QuickFilter? _quickFilter;
  final Set<String> _typeFilters = {};

  List<ScheduleEntry> _filterSwims(List<ScheduleEntry> source) {
    var swims = SwimSessionPresenter.sorted(source);
    final today = OttawaTime.todayDate();
    final now = OttawaTime.nowTime();

    if (_quickFilter != null) {
      swims = swims.where((s) {
        switch (_quickFilter!) {
          case QuickFilter.swimmingNow:
            return s.date == today &&
                SwimSessionPresenter.statusFor(s).status ==
                    SwimSessionStatus.active;
          case QuickFilter.withinOneHour:
            if (s.date != today) return false;
            final startM = _minutes(s.startTime);
            final nowM = _minutes(now);
            return startM >= nowM && startM <= nowM + 60;
          case QuickFilter.tonight:
            return s.date == today && s.startTime.compareTo('17:00') >= 0;
          case QuickFilter.tomorrow:
            final tomorrow = OttawaTime.formatDate(
              DateTime.now().add(const Duration(days: 1)),
            );
            return s.date == tomorrow;
          case QuickFilter.thisWeekend:
            if (s.date == null) return false;
            final wd = DateTime.parse(s.date!).weekday;
            return wd == DateTime.saturday || wd == DateTime.sunday;
        }
      }).toList();
    }

    if (_typeFilters.isNotEmpty) {
      swims = swims.where((s) => _typeFilters.contains(s.category)).toList();
    }
    return swims;
  }

  int _minutes(String time) {
    final p = time.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final sections = state.homeSections;
    final filtering = _quickFilter != null || _typeFilters.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upcoming Swims'),
        actions: [
          IconButton(
            icon: const Icon(Icons.apartment),
            tooltip: 'Browse facilities',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FacilitiesScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: state.isSyncing ? null : state.refreshAll,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: state.refreshAll,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DataFreshnessCard(state: state),
            SyncProgressBanner(state: state),
            const SizedBox(height: 12),
            if (sections.tonight.isNotEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.nightlight),
                  title: const Text('Tonight'),
                  subtitle: Text(
                    '${sections.tonight.length} swim${sections.tonight.length == 1 ? '' : 's'} after 5 PM',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TonightScreen()),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            SwimQuickFilterChips(
              selected: _quickFilter,
              onSelected: (f) => setState(
                () => _quickFilter = f == _quickFilter ? null : f,
              ),
            ),
            const SizedBox(height: 8),
            SwimTypeFilterChips(
              selected: _typeFilters,
              onChanged: (next) => setState(() {
                _typeFilters
                  ..clear()
                  ..addAll(next);
              }),
            ),
            const SizedBox(height: 16),
            if (state.isLoading)
              const LinearProgressIndicator()
            else if (!filtering)
              Text(
                '${sections.swimmingNow.length} swimming now',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            const SizedBox(height: 8),
            if (filtering)
              ..._buildFilteredList(
                context,
                state,
                _filterSwims(state.homeUpcomingSwims),
              )
            else ...[
              _section(context, state, 'Swimming Now', sections.swimmingNow),
              _section(context, state, 'Starting Soon', sections.startingSoon),
              _section(context, state, 'Tonight', sections.tonight),
              _section(context, state, 'Tomorrow', sections.tomorrow),
              if (sections.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 32),
                  child: Center(
                    child: Text(
                      'No upcoming swims found.\nTry Manual Sync in Settings.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFilteredList(
    BuildContext context,
    AppState state,
    List<ScheduleEntry> swims,
  ) {
    if (swims.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.only(top: 32),
          child: Center(
            child: Text(
              'No upcoming swims match your filters.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ];
    }
    return swims.map((swim) => _swimCard(context, state, swim)).toList();
  }

  Widget _section(
    BuildContext context,
    AppState state,
    String title,
    List<ScheduleEntry> swims,
  ) {
    if (swims.isEmpty) return const SizedBox.shrink();
    final filtered = _filterSwims(swims);
    if (filtered.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Row(
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (title == 'Tonight') ...[
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TonightScreen()),
                  ),
                  child: const Text('View all'),
                ),
              ],
            ],
          ),
        ),
        ...filtered.take(8).map((swim) => _swimCard(context, state, swim)),
        if (filtered.length > 8)
          TextButton(
            onPressed: () => setState(() {
              _quickFilter = switch (title) {
                'Swimming Now' => QuickFilter.swimmingNow,
                'Starting Soon' => QuickFilter.withinOneHour,
                'Tonight' => QuickFilter.tonight,
                'Tomorrow' => QuickFilter.tomorrow,
                _ => _quickFilter,
              };
            }),
            child: Text('Show all ${filtered.length}'),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _swimCard(BuildContext context, AppState state, ScheduleEntry swim) =>
      ScheduleSessionCard(
        entry: swim,
        showFacility: true,
        isStale: state.isFacilityStale(swim.facilityId),
        highlight: titleIsActive(swim),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FacilityScreen(facilityId: swim.facilityId),
          ),
        ),
        onExport: swim.date != null
            ? () => showCalendarExportSheet(context, entry: swim)
            : null,
      );

  bool titleIsActive(ScheduleEntry swim) =>
      SwimSessionPresenter.statusFor(swim).status == SwimSessionStatus.active;
}
