import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../di/injection.dart';
import '../../domain/entities/schedule_entry.dart';
import '../../data/services/facility_interaction_service.dart';
import '../providers/app_state.dart';
import '../screens/facility_screen.dart';
import 'navigation_launch_button.dart';
import 'save_swim_sheet.dart';
import 'swim_session_presenter.dart';

/// Consumer-style swim card used on Home and Map sheets.
class HomeSwimCard extends StatefulWidget {
  const HomeSwimCard({
    super.key,
    required this.entry,
    this.highlight = false,
    this.compact = false,
    this.habitHint,
  });

  final ScheduleEntry entry;
  final bool highlight;
  final bool compact;
  final String? habitHint;

  @override
  State<HomeSwimCard> createState() => _HomeSwimCardState();
}

class _HomeSwimCardState extends State<HomeSwimCard> {
  @override
  void initState() {
    super.initState();
    unawaited(
      getIt<FacilityInteractionService>().recordImpression(widget.entry.facilityId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final theme = Theme.of(context);
    final entry = widget.entry;
    final facility = state.facilityFor(entry.facilityId);
    final status = SwimSessionPresenter.statusFor(entry);

    return Card(
      margin: EdgeInsets.symmetric(vertical: widget.compact ? 4 : 6),
      elevation: widget.highlight ? 1 : 0,
      color: widget.highlight
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
          : theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await getIt<FacilityInteractionService>().recordSwimDetailClick(
            entry.facilityId,
            swimStartTime: entry.startTime,
            swimDate: entry.date,
          );
          if (!context.mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FacilityScreen(facilityId: entry.facilityId),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.facilityName ?? facility?.name ?? 'Pool',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          SwimSessionPresenter.sessionTitle(entry),
                          style: theme.textTheme.bodyLarge,
                        ),
                        Text(
                          SwimSessionPresenter.formatRange(entry),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (widget.habitHint != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            widget.habitHint!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.secondary,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Flexible(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: _statusChip(context, status.label, status.status),
                    ),
                  ),
                ],
              ),
              if (!widget.compact) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (entry.distanceKm != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Text(
                          '${entry.distanceKm!.toStringAsFixed(1)} km',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (facility != null &&
                        facility.latitude != null &&
                        facility.longitude != null)
                      NavigationLaunchButton(
                        latitude: facility.latitude!,
                        longitude: facility.longitude!,
                        title: facility.name,
                        facilityId: facility.id,
                        swimStartTime: entry.startTime,
                        swimDate: entry.date,
                        compact: true,
                      ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.bookmark_add_outlined),
                      tooltip: 'Save swim',
                      onPressed: () => showSaveSwimSheet(
                        context,
                        entry: entry,
                        onSave: ({reminderMinutes, asRecurring = false}) =>
                            state.saveSwim(
                          entry,
                          reminderMinutes: reminderMinutes,
                          asRecurring: asRecurring,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusChip(
    BuildContext context,
    String label,
    SwimSessionStatus status,
  ) {
    final theme = Theme.of(context);
    final color = switch (status) {
      SwimSessionStatus.active => theme.colorScheme.primary,
      SwimSessionStatus.upcoming => theme.colorScheme.tertiary,
      SwimSessionStatus.ended => theme.colorScheme.outline,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
