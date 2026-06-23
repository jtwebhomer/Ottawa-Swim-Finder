import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { Classification } from './classification.js';
import {
  evaluateScheduleWrite,
  inferExistingQuality,
  scoreForClassification,
  QualityScore,
} from './dataSafety.js';

describe('dataSafety', () => {
  it('never overwrites live data with empty parse failure', () => {
    const existing = inferExistingQuality({ liveCount: 50, fixtureCount: 0 });
    const write = evaluateScheduleWrite({
      newClassification: Classification.PARSE_FAILED,
      newSessionCount: 0,
      existingQuality: existing,
      existingSessionCount: 50,
    });
    assert.equal(write.apply, false);
    assert.equal(write.finalClassification, Classification.STALE);
  });

  it('never overwrites live data with blocked scrape', () => {
    const existing = inferExistingQuality({ liveCount: 20, fixtureCount: 0 });
    const write = evaluateScheduleWrite({
      newClassification: Classification.BLOCKED,
      newSessionCount: 0,
      existingQuality: existing,
      existingSessionCount: 20,
    });
    assert.equal(write.apply, false);
    assert.equal(write.finalClassification, Classification.STALE);
  });

  it('allows live upgrade when new data is valid', () => {
    const existing = inferExistingQuality({ liveCount: 0, fixtureCount: 30 });
    const write = evaluateScheduleWrite({
      newClassification: Classification.LIVE_OK,
      newSessionCount: 40,
      existingQuality: existing,
      existingSessionCount: 30,
    });
    assert.equal(write.apply, true);
    assert.equal(write.finalClassification, Classification.LIVE_OK);
  });

  it('scores LIVE_OK above FIXTURE', () => {
    assert.ok(scoreForClassification(Classification.LIVE_OK) > scoreForClassification(Classification.FIXTURE_ONLY));
    assert.equal(scoreForClassification(Classification.LIVE_OK), QualityScore.LIVE_OK);
  });

  it('allows confirmed empty only when no prior sessions', () => {
    const existing = inferExistingQuality({ liveCount: 0, fixtureCount: 0 });
    const write = evaluateScheduleWrite({
      newClassification: Classification.CONFIRMED_EMPTY,
      newSessionCount: 0,
      existingQuality: existing,
      existingSessionCount: 0,
    });
    assert.equal(write.apply, true);
  });
});
