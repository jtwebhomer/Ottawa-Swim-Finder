import 'package:flutter_test/flutter_test.dart';

import 'package:ottawa_swim_finder/data/services/facility_discovery_service.dart';
import 'package:ottawa_swim_finder/domain/entities/facility_type.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('canonical inventory includes outdoor and wading pools with coordinates', () async {
    final canonical = await FacilityDiscoveryService().loadCanonicalFacilities();
    final outdoor = canonical.where((f) => f.facilityType == FacilityType.outdoorPool);
    final wading = canonical.where((f) => f.facilityType == FacilityType.wadingPool);

    expect(outdoor.length, greaterThanOrEqualTo(9));
    expect(wading.length, greaterThanOrEqualTo(1));
    for (final f in [...outdoor, ...wading]) {
      expect(f.latitude, isNotNull);
      expect(f.longitude, isNotNull);
    }
  });
}
