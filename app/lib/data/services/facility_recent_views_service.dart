import '../../domain/repositories/repositories.dart';
import 'facility_interaction_service.dart';

/// Legacy wrapper — delegates to [FacilityInteractionService].
class FacilityRecentViewsService {
  FacilityRecentViewsService(this._interactions);

  final FacilityInteractionService _interactions;

  Future<void> recordView(String facilityId) =>
      _interactions.recordView(facilityId);

  Future<Set<String>> recentFacilityIds({int max = 8}) =>
      _interactions.recentFacilityIds(max: max);
}
