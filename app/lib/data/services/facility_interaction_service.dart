import '../../domain/entities/facility_interaction.dart';
import '../../domain/entities/habit_event.dart';
import '../../domain/repositories/repositories.dart';
import 'habit_detection_service.dart';

/// Records and reads per-facility user interaction signals.
class FacilityInteractionService {
  FacilityInteractionService(
    this._repo, {
    HabitDetectionService? habitDetection,
  }) : _habits = habitDetection;

  final FacilityInteractionRepository _repo;
  final HabitDetectionService? _habits;
  final Set<String> _sessionImpressions = {};

  Future<Map<String, FacilityInteractionMetrics>> getAllMetrics() =>
      _repo.getAllMetrics();

  Future<void> recordView(String facilityId) async {
    await _repo.incrementView(facilityId);
    await _habits?.recordAction(
      facilityId: facilityId,
      action: HabitActionType.view,
    );
  }

  Future<void> recordSwimDetailClick(
    String facilityId, {
    String? swimStartTime,
    String? swimDate,
  }) async {
    await _repo.incrementSwimDetailClick(facilityId);
    await _repo.incrementView(facilityId);
    await _habits?.recordAction(
      facilityId: facilityId,
      action: HabitActionType.click,
      swimStartTime: swimStartTime,
      swimDate: swimDate,
    );
  }

  Future<void> recordFavorite(String facilityId) async {
    await _repo.incrementSaved(facilityId);
    await _habits?.recordAction(
      facilityId: facilityId,
      action: HabitActionType.save,
    );
  }

  Future<void> recordUnfavorite(String facilityId) =>
      _repo.decrementSaved(facilityId);

  Future<void> recordDirections(
    String facilityId, {
    String? swimStartTime,
    String? swimDate,
  }) async {
    await _habits?.recordAction(
      facilityId: facilityId,
      action: HabitActionType.directions,
      swimStartTime: swimStartTime,
      swimDate: swimDate,
    );
  }

  Future<void> recordSaveSwim(
    String facilityId, {
    required String swimStartTime,
    String? swimDate,
  }) async {
    await _repo.incrementSaved(facilityId);
    await _habits?.recordAction(
      facilityId: facilityId,
      action: HabitActionType.save,
      swimStartTime: swimStartTime,
      swimDate: swimDate,
    );
  }

  Future<void> recordImpression(String facilityId) async {
    if (!_sessionImpressions.add(facilityId)) return;
    await _repo.incrementImpression(facilityId);
  }

  Future<void> recordIgnore(String facilityId) =>
      _repo.incrementIgnore(facilityId);

  Future<Set<String>> recentFacilityIds({int max = 8}) async {
    final all = await _repo.getAllMetrics();
    final sorted = all.values.toList()
      ..sort((a, b) => (b.lastViewedAt ?? 0).compareTo(a.lastViewedAt ?? 0));
    return sorted.take(max).map((m) => m.facilityId).toSet();
  }

  void resetSessionImpressions() => _sessionImpressions.clear();
}
