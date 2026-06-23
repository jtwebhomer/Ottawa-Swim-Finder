import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Reads the latest saved HTML snapshot for a facility (Tier 3 replay).
class HtmlSnapshotCache {
  Future<String?> loadLatestHtml(String facilityId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final snapshotsDir = Directory('${dir.path}/snapshots');
      if (!await snapshotsDir.exists()) return null;

      final prefix = '${facilityId}_';
      final files = await snapshotsDir
          .list()
          .where((e) => e is File && e.path.contains(prefix))
          .cast<File>()
          .toList();

      if (files.isEmpty) return null;

      files.sort(
        (a, b) => b.path.compareTo(a.path),
      );
      return files.first.readAsStringSync();
    } catch (_) {
      return null;
    }
  }
}
