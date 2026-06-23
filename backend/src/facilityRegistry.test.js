import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  resolveFacilityRecord,
  DataModel,
  FacilityType,
  usesSwimSchedulePipeline,
  usesSeasonalPipeline,
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
  });

  it('classifies outdoor as MIXED_SEASONAL', () => {
    const reg = resolveFacilityRecord({
      id: 'bearbrook-pool',
      name: 'Bearbrook Pool',
      facility_type: 'OUTDOOR_POOL',
    });
    assert.equal(reg.dataModel, DataModel.MIXED_SEASONAL);
    assert.equal(reg.hasSwimSchedule, false);
  });
});
