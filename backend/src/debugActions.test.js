import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { buildDebugAction, resolveDebugReason } from './debugActions.js';
import { Classification } from './classification.js';
import { facilityUrl } from './facilityUrls.js';

describe('debugActions', () => {
  it('enables facility page link for BLOCKED swim facility', () => {
    const d = buildDebugAction({
      id: 'brewer-pool-and-arena',
      scrape_classification: Classification.BLOCKED_HARD,
      has_swim_schedule: true,
      data_model: 'SWIM_SCHEDULE',
    });
    assert.equal(d.can_debug, true);
    assert.equal(d.reason, 'bot_challenge');
    assert.equal(d.debug_url, facilityUrl('brewer-pool-and-arena'));
  });

  it('enables facility page link for PARSE_FAILED', () => {
    const d = buildDebugAction({
      id: 'plant-recreation-centre',
      scrape_classification: Classification.PARSE_FAILED,
      data_model: 'SWIM_SCHEDULE',
    });
    assert.equal(d.can_debug, true);
    assert.equal(d.reason, 'parse_failed');
  });

  it('does NOT enable link for wading HOURS_ONLY', () => {
    const d = buildDebugAction({
      id: 'owl-park-wading-pool',
      schedule_mode: 'OPEN_HOURS_ONLY',
      data_model: 'HOURS_ONLY',
      type: 'WADING_POOL',
      sync_status: 'open_hours',
    });
    assert.equal(d.can_debug, false);
    assert.equal(d.debug_url, null);
  });

  it('does NOT enable link for splash pad STATUS_ONLY', () => {
    assert.equal(
      resolveDebugReason({
        id: 'splash-1',
        type: 'SPLASH_PAD',
        data_model: 'HOURS_ONLY',
        schedule_mode: 'OPEN_HOURS_ONLY',
      }),
      null,
    );
  });

  it('enables link for INCOMPLETE render on swim facility', () => {
    const d = buildDebugAction({
      id: 'nepean-sportsplex',
      data_model: 'SWIM_SCHEDULE',
      render_status: 'INCOMPLETE',
    });
    assert.equal(d.can_debug, true);
    assert.equal(d.reason, 'incomplete');
  });
});
