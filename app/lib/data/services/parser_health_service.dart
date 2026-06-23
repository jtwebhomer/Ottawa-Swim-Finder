import '../../domain/repositories/repositories.dart';

/// Parser health metrics persisted after each successful Ottawa parse.
class ParserHealthSnapshot {
  const ParserHealthSnapshot({
    this.lastSuccessfulParseAt,
    this.facilitiesParsed = 0,
    this.totalFacilities = 0,
    this.futureSessionsParsed = 0,
    this.unknownCategoryCount = 0,
    this.status = 'Unknown',
    this.anomalyWarning,
  });

  final DateTime? lastSuccessfulParseAt;
  final int facilitiesParsed;
  final int totalFacilities;
  final int futureSessionsParsed;
  final int unknownCategoryCount;
  final String status;
  final String? anomalyWarning;

  String get facilitiesLabel =>
      totalFacilities > 0 ? '$facilitiesParsed / $totalFacilities' : '$facilitiesParsed';
}

class ParserHealthService {
  ParserHealthService(this._settings);

  final SettingsRepository _settings;
  static const _prefix = 'parser_health_';

  Future<void> recordSuccessfulParse({
    required int facilitiesParsed,
    required int totalFacilities,
    required int futureSessions,
    required int unknownCategories,
    String? anomalyWarning,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _settings.setString('${_prefix}last_success_at', now.toString());
    await _settings.setString(
      '${_prefix}facilities_parsed',
      facilitiesParsed.toString(),
    );
    await _settings.setString(
      '${_prefix}total_facilities',
      totalFacilities.toString(),
    );
    await _settings.setString(
      '${_prefix}future_sessions',
      futureSessions.toString(),
    );
    await _settings.setString(
      '${_prefix}unknown_categories',
      unknownCategories.toString(),
    );
    await _settings.setString('${_prefix}status', _statusLabel(
      facilitiesParsed: facilitiesParsed,
      totalFacilities: totalFacilities,
      anomalyWarning: anomalyWarning,
    ));
    if (anomalyWarning != null) {
      await _settings.setString('${_prefix}anomaly_warning', anomalyWarning);
    } else {
      await _settings.setString('${_prefix}anomaly_warning', '');
    }
  }

  Future<void> recordRejectedParse(String reason) async {
    await _settings.setString('${_prefix}status', 'Rejected');
    await _settings.setString('${_prefix}anomaly_warning', reason);
  }

  Future<ParserHealthSnapshot> load() async {
    final raw = await _settings.getString('${_prefix}last_success_at');
    final ms = int.tryParse(raw ?? '');
    final warning = await _settings.getString('${_prefix}anomaly_warning');

    Future<int> readInt(String key) async =>
        int.tryParse(await _settings.getString('$_prefix$key') ?? '') ?? 0;

    return ParserHealthSnapshot(
      lastSuccessfulParseAt:
          ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
      facilitiesParsed: await readInt('facilities_parsed'),
      totalFacilities: await readInt('total_facilities'),
      futureSessionsParsed: await readInt('future_sessions'),
      unknownCategoryCount: await readInt('unknown_categories'),
      status: await _settings.getString('${_prefix}status') ?? 'Unknown',
      anomalyWarning: (warning != null && warning.isNotEmpty) ? warning : null,
    );
  }

  String _statusLabel({
    required int facilitiesParsed,
    required int totalFacilities,
    String? anomalyWarning,
  }) {
    if (anomalyWarning != null && anomalyWarning.isNotEmpty) return 'Warning';
    if (totalFacilities > 0 && facilitiesParsed >= totalFacilities) {
      return 'Good';
    }
    if (facilitiesParsed > 0) return 'Partial';
    return 'Unknown';
  }
}
