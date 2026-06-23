import 'package:flutter_test/flutter_test.dart';
import 'package:ottawa_swim_finder/data/services/facility_discovery_service.dart';
import 'package:ottawa_swim_finder/data/services/facility_slug_registry.dart';

void main() {
  const sampleHtml = '''
<html><body>
<h3>Central</h3>
<ul>
<li>Brewer Pool and Arena, 100 Brewer Way</li>
<li>Plant Recreation Centre, 930 Somerset Street West</li>
</ul>
<h3>East</h3>
<ul>
<li>Splash Wave Pool, 2040 Ogilvie Road</li>
</ul>
</body></html>
''';

  test('parses indoor listing regions and resolves slugs', () {
    final service = FacilityDiscoveryService();
    final rows = service.parseIndoorListingForTest(sampleHtml);

    expect(rows.length, 3);
    expect(rows.first.slug, 'brewer-pool-and-arena');
    expect(rows.first.region, 'central');
    expect(rows.first.slugResolution, 'registry');
    expect(
      rows.map((r) => r.slug),
      contains('splash-wave-pool'),
    );
  });

  test('slug registry maps known fragments', () {
    expect(
      FacilitySlugRegistry.slugForName('Bob MacQuarrie Recreation Complex'),
      'bob-macquarrie-recreation-complex-orleans',
    );
  });
}
