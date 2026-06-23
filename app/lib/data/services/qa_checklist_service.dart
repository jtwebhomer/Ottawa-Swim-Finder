import '../../domain/repositories/repositories.dart';

enum QaTestStatus { pass, fail, notTested }

class QaTestItem {
  const QaTestItem({
    required this.id,
    required this.label,
    required this.status,
  });

  final String id;
  final String label;
  final QaTestStatus status;

  QaTestItem copyWith({QaTestStatus? status}) => QaTestItem(
        id: id,
        label: label,
        status: status ?? this.status,
      );
}

/// Built-in beta QA checklist stored locally in settings.
class QaChecklistService {
  QaChecklistService(this._settings);

  final SettingsRepository _settings;
  static const _prefix = 'qa_test_';

  static const defaultTests = [
    ('fresh_install', 'Fresh Install Test'),
    ('offline', 'Offline Test'),
    ('reminder', 'Reminder Test'),
    ('map_consistency', 'Map Consistency Test'),
    ('calendar_future', 'Calendar Future Date Test'),
    ('version_sync', 'Version Update Sync Test'),
  ];

  Future<List<QaTestItem>> loadAll() async {
    final items = <QaTestItem>[];
    for (final (id, label) in defaultTests) {
      final raw = await _settings.getString('$_prefix$id');
      items.add(
        QaTestItem(
          id: id,
          label: label,
          status: _parseStatus(raw),
        ),
      );
    }
    return items;
  }

  Future<void> setStatus(String id, QaTestStatus status) async {
    await _settings.setString('$_prefix$id', status.name);
  }

  QaTestStatus _parseStatus(String? raw) => switch (raw) {
        'pass' => QaTestStatus.pass,
        'fail' => QaTestStatus.fail,
        _ => QaTestStatus.notTested,
      };
}
