import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:ottawa_swim_finder/core/constants/http_constants.dart';
import 'package:ottawa_swim_finder/data/scraper/parsers/schedule_parser.dart';
import 'package:ottawa_swim_finder/data/services/facility_parser_audit_service.dart';

/// Deep facility audit — run: dart run tool/facility_audit.dart <facility-id>
Future<void> main(List<String> args) async {
  final id = args.isNotEmpty ? args.first : 'plant-recreation-centre';
  final url =
      'https://ottawa.ca/en/recreation-and-parks/facilities/place-listing/$id';

  final response = await http.get(
    Uri.parse(url),
    headers: HttpConstants.headersForUrl(url),
  );

  if (response.statusCode != 200) {
    stderr.writeln('HTTP ${response.statusCode}');
    exit(1);
  }

  final html = response.body;
  if (html.toLowerCase().contains('pardon our interruption')) {
    stderr.writeln('Blocked page');
    exit(1);
  }

  final snapDir = Directory('test/fixtures/snapshots');
  await snapDir.create(recursive: true);
  await File('${snapDir.path}/$id.html').writeAsString(html);

  final parser = ScheduleParser();
  final auditService = FacilityParserAuditService(parser: parser);
  final report = auditService.audit(
    html: html,
    facilityId: id,
    facilityName: id,
    dayHorizon: 14,
  );

  print(auditService.formatReport(report));

  final jsonPath = '${snapDir.path}/$id.audit.json';
  await File(jsonPath).writeAsString(
    jsonEncode({
      'facilityId': report.facilityId,
      'totalSessions': report.totalExpandedSessions,
      'futureSessions': report.futureSessionCount,
      'tables': report.tables
          .map(
            (t) => {
              'title': t.title,
              'season': t.dateRangeLabel,
              'scheduleType': t.scheduleType,
              'rawEntries': t.rawEntryCount,
              'weekdayColumns': t.dayColumns,
              'dateColumns': t.specialDateColumns,
              'headers': t.headers,
            },
          )
          .toList(),
      'sessionCountsByDate': report.sessionCountsByDate,
    }),
  );

  print('\nJSON audit: $jsonPath');
  print('Snapshot: test/fixtures/snapshots/$id.html');
}
