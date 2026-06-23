import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  resolveFacilityRecord,
  DataModel,
  FacilityType,
  usesSwimSchedulePipeline,
  usesSeasonalPipeline,
  loadFacilityRegistry,
  assertFacilityCoverage,
  ALL_AQUATIC_TYPES,
  EXPECTED_MINIMUMS,
  labelForFacilityType,
} from './facilityRegistry.js';

describe('facilityRegistry', () => {
  it('classifies indoor pool as SWIM_SCHEDULE before scrape', () => {
    const reg = resolveFacilityRecord({
      id: 'plant-recreation-centre',
      name: 'Plant',
      facility_type: 'INDOOR_POOL',
    });
    assert.equal(reg.type, FacilityType.INDOOR_POOL);
    assert.equal(reg.dataModel, DataModel.SWIM_SCHEDULE);
    assert.equal(reg.hasSwimSchedule, true);
    assert.equal(usesSwimSchedulePipeline(reg), true);
  });

  it('classifies wading as HOURS_ONLY — not a schedule failure', () => {
    const reg = resolveFacilityRecord({
      id: 'canterbury-wading-pool',
      name: 'Canterbury Wading Pool',
      facility_type: 'WADING_POOL',
      schedule_mode: 'OPEN_HOURS_ONLY',
    });
    assert.equal(reg.dataModel, DataModel.HOURS_ONLY);
    assert.equal(reg.hasSwimSchedule, false);
    assert.equal(usesSeasonalPipeline(reg), true);
    assert.equal(usesSwimSchedulePipeline(reg), false);
    assert.equal(labelForFacilityType(FacilityType.WADING_POOL), 'Open Hours Only');
  });

  it('classifies outdoor as MIXED_SEASONAL', () => {
    const reg = resolveFacilityRecord({
      id: 'bearbrook-pool',
      name: 'Bearbrook Pool',
      facility_type: 'OUTDOOR_POOL',
    });
    assert.equal(reg.dataModel, DataModel.MIXED_SEASONAL);
    assert.equal(reg.hasSwimSchedule, false);
    assert.equal(labelForFacilityType(FacilityType.OUTDOOR_POOL), 'Seasonal Schedule');
  });

  it('classifies splash pad as HOURS_ONLY', () => {
    const reg = resolveFacilityRecord({
      id: 'test-splash',
      name: 'Test Splash Pad',
      facility_type: 'SPLASH_PAD',
    });
    assert.equal(reg.dataModel, DataModel.HOURS_ONLY);
    assert.equal(labelForFacilityType(FacilityType.SPLASH_PAD), 'Seasonal Activity Area');
  });

  it('registry meets Ottawa minimum coverage', () => {
    const registry = loadFacilityRegistry();
    const result = assertFacilityCoverage(registry);
    assert.ok(result.total >= 57);
    assert.ok(result.indoorAquatic >= EXPECTED_MINIMUMS.INDOOR_AQUATIC);
    assert.equal(ALL_AQUATIC_TYPES.length, 5);
  });
});
