import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';
import '../../data/services/calendar_export_service.dart';
import '../../domain/entities/facility.dart';
import '../../domain/entities/schedule_entry.dart';
import '../widgets/swim_session_presenter.dart';

Future<void> showCalendarExportSheet(
  BuildContext context, {
  required ScheduleEntry entry,
  Facility? facility,
  CalendarExportService? exportService,
}) {
  final service = exportService ?? CalendarExportService();
  final title =
      '${SwimCategories.displayName(category: entry.category, rawName: entry.rawCategory)} — ${facility?.name ?? entry.facilityName ?? entry.facilityId}';

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Export to Calendar', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '${SwimSessionPresenter.formatRange(entry)}\n'
            '${facility?.name ?? entry.facilityName ?? entry.facilityId}',
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.event),
            title: const Text('Add to Google Calendar'),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                final uri = service.googleCalendarUrl(
                  entry: entry,
                  title: title,
                  facilityName: facility?.name ?? entry.facilityName,
                  address: facility?.address,
                );
                await service.openGoogleCalendar(uri);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not open calendar. Try again in a moment.'),
                    ),
                  );
                }
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy .ics to clipboard'),
            subtitle: const Text('Paste into calendar apps that accept ICS'),
            onTap: () async {
              Navigator.pop(ctx);
              try {
                final ics = service.buildIcs(
                  entry: entry,
                  title: title,
                  facilityName: facility?.name ?? entry.facilityName,
                  address: facility?.address,
                );
                await Clipboard.setData(ClipboardData(text: ics));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ICS copied to clipboard')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not open calendar. Try again in a moment.'),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    ),
  );
}
