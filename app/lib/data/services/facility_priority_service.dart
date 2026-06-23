import '../../domain/entities/facility.dart';
import '../../domain/entities/facility_priority.dart';
import '../../domain/entities/facility_score.dart';
import '../../domain/entities/sync_location_context.dart';
import 'facility_ranking_service.dart';

/// Backward-compatible facade over [FacilityRankingService] for smart sync.
class FacilityPriorityService {
  FacilityPriorityService(this._rankingService);

  final FacilityRankingService _rankingService;

  List<FacilityPriorityScore> get lastRankings => _rankingService.lastRankings;

  List<FacilityScoreBreakdown> get lastBreakdowns =>
      _rankingService.lastBreakdowns;

  Future<FacilityRankingContext> buildContext({
    required List<Facility> facilities,
    required SyncLocationContext anchor,
    required int staleThresholdHours,
    DateTime? now,
  }) =>
      _rankingService.buildContext(
        facilities: facilities,
        anchor: anchor,
        staleThresholdHours: staleThresholdHours,
        now: now,
      );

  List<FacilityPriorityScore> rankFacilities({
    required List<Facility> facilities,
    required FacilityRankingContext context,
    Set<String> backoffFacilityIds = const {},
  }) {
    _rankingService.scoreFacilities(
      facilities: facilities,
      context: context,
      backoffFacilityIds: backoffFacilityIds,
    );
    return _rankingService.lastRankings;
  }
}

/// Legacy alias — prefer [FacilityRankingContext].
typedef FacilityPriorityContext = FacilityRankingContext;
