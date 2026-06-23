import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../widgets/calendar_export_sheet.dart';
import '../widgets/schedule_session_card.dart';
import '../widgets/save_swim_sheet.dart';
import '../widgets/swim_session_presenter.dart';
import 'facility_screen.dart';

/// Chronological list of swims starting at 5 PM today city-wide.
class TonightScreen extends StatelessWidget {
  const TonightScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final tonight = SwimSessionPresenter.sorted(state.homeSections.tonight);

    return Scaffold(
      appBar: AppBar(title: const Text('Tonight')),
      body: tonight.isEmpty
          ? Center(
              child: Text(
                'No swims scheduled tonight after 5 PM.\n'
                'Check Tomorrow or Find Swim.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: tonight.length,
              itemBuilder: (context, index) {
                final swim = tonight[index];
                return ScheduleSessionCard(
                  entry: swim,
                  showFacility: true,
                  isStale: state.isFacilityStale(swim.facilityId),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FacilityScreen(facilityId: swim.facilityId),
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
                  onExport: swim.date != null
                      ? () => showCalendarExportSheet(context, entry: swim)
                      : null,
                );
              },
            ),
    );
  }
}
