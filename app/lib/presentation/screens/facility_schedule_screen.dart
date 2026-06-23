import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/ottawa_time.dart';
import '../../data/services/facility_availability_presenter.dart';
import '../../di/injection.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/facility_type.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../domain/repositories/repositories.dart';
import '../widgets/schedule_session_card.dart';
import '../widgets/swim_session_presenter.dart';

enum FacilityScheduleTab { today, tomorrow, thisWeek, allUpcoming }

/// Ottawa.ca-style grouped facility schedule with date tabs.
class FacilityScheduleScreen extends StatefulWidget {
  const FacilityScheduleScreen({
    super.key,
    required this.facilityId,
    this.initialTab = FacilityScheduleTab.today,
  });

  final String facilityId;
  final FacilityScheduleTab initialTab;

  @override
  State<FacilityScheduleScreen> createState() => _FacilityScheduleScreenState();
}

class _FacilityScheduleScreenState extends State<FacilityScheduleScreen>
    with SingleTickerProviderStateMixin {
  Facility? _facility;
  bool _loading = true;
  late TabController _tabController;
  final _cache = <FacilityScheduleTab, List<ScheduleEntry>>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: FacilityScheduleTab.values.length,
      vsync: this,
      initialIndex: widget.initialTab.index,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        _loadTab(FacilityScheduleTab.values[_tabController.index]);
      }
    });
    _bootstrap();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final facility =
        await getIt<FacilityRepository>().getFacilityById(widget.facilityId);
    if (!mounted) return;
    setState(() {
      _facility = facility;
      _loading = false;
    });
    await _loadTab(widget.initialTab);
  }

  Future<void> _loadTab(FacilityScheduleTab tab) async {
    if (_cache.containsKey(tab)) return;

    final repo = getIt<ScheduleRepository>();
    final today = OttawaTime.todayDate();
    final todayDt = DateTime.parse(today);
    final tomorrow = OttawaTime.formatDate(todayDt.add(const Duration(days: 1)));
    final weekEnd = OttawaTime.formatDate(todayDt.add(const Duration(days: 6)));

    final entries = switch (tab) {
      FacilityScheduleTab.today => await repo.getTimelineForDate(
          today,
          facilityId: widget.facilityId,
        ),
      FacilityScheduleTab.tomorrow => await repo.getTimelineForDate(
          tomorrow,
          facilityId: widget.facilityId,
        ),
      FacilityScheduleTab.thisWeek => await repo.getSchedulesForFacilityBetween(
          facilityId: widget.facilityId,
          startDate: today,
          endDate: weekEnd,
        ),
      FacilityScheduleTab.allUpcoming => await repo.getUpcomingSwims(
          facilityId: widget.facilityId,
          limit: 1000,
        ),
    };

    if (!mounted) return;
    setState(() {
      _cache[tab] = SwimSessionPresenter.sorted(entries);
    });
  }

  String _lastUpdatedLabel() {
    final facility = _facility;
    if (facility?.lastSuccessfulSyncAt != null) {
      return DateFormat.yMMMd().add_jm().format(
            DateTime.fromMillisecondsSinceEpoch(facility!.lastSuccessfulSyncAt!),
          );
    }
    if (facility?.lastUpdated != null) {
      return DateFormat.yMMMd().add_jm().format(
            DateTime.fromMillisecondsSinceEpoch(facility!.lastUpdated!),
          );
    }
    return 'Bundled schedules';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final facility = _facility;
    if (facility == null) {
      return const Scaffold(
        body: Center(child: Text('Facility not found')),
      );
    }

    if (!facility.usesSwimScheduleUi) {
      return Scaffold(
        appBar: AppBar(title: Text(facility.name)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _FacilityScheduleHeader(
              facility: facility,
              lastUpdated: _lastUpdatedLabel(),
            ),
            const SizedBox(height: 16),
            Text(
              FacilityAvailabilityPresenter.headline(facility),
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              FacilityAvailabilityPresenter.detail(facility),
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Text(
              'Visit ottawa.ca for the latest seasonal hours and status.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(facility.name),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Today'),
            Tab(text: 'Tomorrow'),
            Tab(text: 'This Week'),
            Tab(text: 'All Upcoming'),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FacilityScheduleHeader(
            facility: facility,
            lastUpdated: _lastUpdatedLabel(),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                for (final tab in FacilityScheduleTab.values)
                  _ScheduleTabBody(
                    entries: _cache[tab],
                    emptyMessage: _emptyMessage(tab, facility),
                    onRefresh: () async {
                      _cache.remove(tab);
                      await _loadTab(tab);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _emptyMessage(FacilityScheduleTab tab, Facility facility) {
    if (!facility.hasSwimSchedule) {
      return facility.nonSwimScheduleLabel;
    }
    return switch (tab) {
      FacilityScheduleTab.today =>
        'No swims scheduled for today. Try Tomorrow or All Upcoming.',
      FacilityScheduleTab.tomorrow =>
        'No swims scheduled for tomorrow. Try This Week or All Upcoming.',
      FacilityScheduleTab.thisWeek =>
        'No swims scheduled this week. Schedules are updating in the background.',
      FacilityScheduleTab.allUpcoming =>
        'No upcoming swims on file. Schedules are updating in the background.',
    };
  }
}

class _FacilityScheduleHeader extends StatelessWidget {
  const _FacilityScheduleHeader({
    required this.facility,
    required this.lastUpdated,
  });

  final Facility facility;
  final String lastUpdated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (facility.address != null && facility.address!.isNotEmpty)
              Text(facility.address!, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text(
              '${facility.aquaticSettingLabel} · ${facility.facilityType.label}'
              '${facility.scheduleMode != FacilityScheduleMode.swimSchedule ? ' · ${facility.scheduleMode.label}' : ''}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Last updated: $lastUpdated',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleTabBody extends StatelessWidget {
  const _ScheduleTabBody({
    required this.entries,
    required this.emptyMessage,
    required this.onRefresh,
  });

  final List<ScheduleEntry>? entries;
  final String emptyMessage;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (entries == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (entries!.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            Text(emptyMessage, textAlign: TextAlign.center),
          ],
        ),
      );
    }

    final grouped = groupSchedulesByDate(entries!);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: grouped.length,
        itemBuilder: (context, index) {
          final group = grouped[index];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Text(
                  formatScheduleDateHeader(group.date),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              for (final entry in group.entries)
                ScheduleSessionCard(entry: entry),
            ],
          );
        },
      ),
    );
  }
}

class ScheduleDateGroup {
  const ScheduleDateGroup({required this.date, required this.entries});

  final String date;
  final List<ScheduleEntry> entries;
}

List<ScheduleDateGroup> groupSchedulesByDate(List<ScheduleEntry> entries) {
  final byDate = <String, List<ScheduleEntry>>{};
  for (final entry in entries) {
    final date = entry.date;
    if (date == null) continue;
    byDate.putIfAbsent(date, () => []).add(entry);
  }

  final dates = byDate.keys.toList()..sort();
  return dates
      .map((date) => ScheduleDateGroup(date: date, entries: byDate[date]!))
      .toList();
}

String formatScheduleDateHeader(String isoDate) {
  final dt = DateTime.parse(isoDate);
  return DateFormat('EEEE MMMM d').format(dt);
}
