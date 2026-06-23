import { Classification } from './classification.js';
import { DisplayStatus } from './facilityRegistry.js';

/** Quality scores — only overwrite when new score strictly exceeds existing. */
export const QualityScore = {
  LIVE_OK: 3,
  STALE: 3,
  CACHED: 3,
  FIXTURE: 2,
  SEASONAL_ONLY: 2,
  OPEN_HOURS_ONLY: 2,
  PARSE_ISSUE: 1,
  PARSE_FAILED: 1,
  RETRY_REQUIRED: 1,
  EMPTY_BUT_EXPECTED: 1,
  BLOCKED: 0,
  CONFIRMED_EMPTY: 0,
  NO_SCHEDULE_DATA: 0,
};

export function scoreForClassification(classification) {
  const map = {
    [Classification.LIVE_OK]: QualityScore.LIVE_OK,
    [Classification.STALE]: QualityScore.STALE,
    [Classification.FIXTURE_ONLY]: QualityScore.FIXTURE,
    [Classification.SEASONAL_ONLY]: QualityScore.SEASONAL_ONLY,
    [Classification.OPEN_HOURS_ONLY]: QualityScore.OPEN_HOURS_ONLY,
    [DisplayStatus.PARSE_ISSUE]: QualityScore.PARSE_ISSUE,
    [Classification.PARSE_FAILED]: QualityScore.PARSE_FAILED,
    [Classification.RETRY_REQUIRED]: QualityScore.RETRY_REQUIRED,
    [Classification.EMPTY_BUT_EXPECTED_SCHEDULES]: QualityScore.EMPTY_BUT_EXPECTED,
    [DisplayStatus.BLOCKED]: QualityScore.BLOCKED,
    [Classification.CONFIRMED_EMPTY]: QualityScore.CONFIRMED_EMPTY,
    [Classification.NO_SCHEDULE_DATA]: QualityScore.NO_SCHEDULE_DATA,
  };
  return map[classification] ?? 0;
}

export function inferExistingQuality({ liveCount, fixtureCount, cachedCount = 0, classification }) {
  if (liveCount > 0) {
    return { score: QualityScore.LIVE_OK, classification: Classification.LIVE_OK, dataSource: 'live' };
  }
  if (cachedCount > 0) {
    return { score: QualityScore.CACHED, classification: Classification.LIVE_OK, dataSource: 'cached' };
  }
  if (fixtureCount > 0) {
    return { score: QualityScore.FIXTURE, classification: Classification.FIXTURE_ONLY, dataSource: 'fixture' };
  }
  if (classification === Classification.SEASONAL_ONLY || classification === Classification.OPEN_HOURS_ONLY) {
    return { score: QualityScore.SEASONAL_ONLY, classification, dataSource: 'unknown' };
  }
  return { score: 0, classification: Classification.NO_SCHEDULE_DATA, dataSource: 'unknown' };
}

/**
 * Decide whether schedule rows may be replaced.
 * Never wipe good data with empty/blocked/parse-failed results.
 */
export function evaluateScheduleWrite({
  newClassification,
  newSessionCount,
  existingQuality,
  existingSessionCount,
  newDataSource = 'live',
}) {
  const newScore = scoreForClassification(newClassification);
  const existingScore = existingQuality.score;

  const destructiveEmpty =
    newSessionCount === 0 &&
    [Classification.CONFIRMED_EMPTY, DisplayStatus.PARSE_ISSUE, Classification.PARSE_FAILED,
      Classification.BLOCKED, Classification.RETRY_REQUIRED, DisplayStatus.BLOCKED].includes(newClassification);

  if (destructiveEmpty && existingSessionCount > 0) {
    return {
      apply: false,
      finalClassification: Classification.STALE,
      reason: 'preserve_existing_sessions',
      newScore,
      existingScore,
    };
  }

  if (
    (newClassification === Classification.LIVE_OK || newClassification === DisplayStatus.LIVE_OK) &&
    newSessionCount > 0
  ) {
    const effectiveNewScore = newScore;
    if (effectiveNewScore >= existingScore || newSessionCount > existingSessionCount) {
      return { apply: true, finalClassification: DisplayStatus.LIVE_OK, reason: 'live_upgrade', newScore: effectiveNewScore, existingScore };
    }
    return {
      apply: false,
      finalClassification: Classification.STALE,
      reason: 'existing_quality_higher',
      newScore,
      existingScore,
    };
  }

  if (newClassification === Classification.CONFIRMED_EMPTY && existingSessionCount === 0) {
    return { apply: true, finalClassification: Classification.CONFIRMED_EMPTY, reason: 'confirmed_empty_no_prior', newScore, existingScore };
  }

  if (newScore > existingScore && newSessionCount > 0) {
    return { apply: true, finalClassification: newClassification, reason: 'score_upgrade', newScore, existingScore };
  }

  if (existingSessionCount > 0 && newScore <= existingScore) {
    return {
      apply: false,
      finalClassification: Classification.STALE,
      reason: 'quality_lock',
      newScore,
      existingScore,
    };
  }

  return {
    apply: false,
    finalClassification: newClassification,
    reason: 'no_write',
    newScore,
    existingScore,
  };
}

export const RETRY_CLASSIFICATIONS = [
  DisplayStatus.BLOCKED,
  DisplayStatus.PARSE_ISSUE,
  'PARSE_FAILED',
  'RETRY_REQUIRED',
];

export const WEEKLY_RETRY_BACKOFF_MS = [2000, 5000, 10000];
export const WEEKLY_MAX_RETRIES = 3;
