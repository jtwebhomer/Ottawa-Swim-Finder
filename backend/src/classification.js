/** Facility scrape classification — accuracy over speed. */
export const Classification = {
  LIVE_OK: 'LIVE_OK',
  STALE: 'STALE',
  BLOCKED: 'BLOCKED',
  BLOCKED_TEMPORARY: 'BLOCKED_TEMPORARY',
  BLOCKED_HARD: 'BLOCKED_HARD',
  PARSE_FAILED: 'PARSE_FAILED',
  PARSE_ISSUE: 'PARSE_ISSUE',
  RETRY_REQUIRED: 'RETRY_REQUIRED',
  SEASONAL_ONLY: 'SEASONAL_ONLY',
  OPEN_HOURS_ONLY: 'OPEN_HOURS_ONLY',
  CONFIRMED_EMPTY: 'CONFIRMED_EMPTY',
  EMPTY_BUT_EXPECTED_SCHEDULES: 'EMPTY_BUT_EXPECTED_SCHEDULES',
  NO_SCHEDULE_DATA: 'NO_SCHEDULE_DATA',
  FIXTURE_ONLY: 'FIXTURE_ONLY',
};

export const RenderStatus = {
  OK: 'OK',
  BLOCKED: 'BLOCKED',
  INCOMPLETE: 'INCOMPLETE',
  UNSTABLE: 'UNSTABLE',
  ERROR: 'ERROR',
};

export const SyncType = {
  WEEKLY_FULL: 'weekly_full',
  REPAIR: 'repair',
  MANUAL: 'manual',
  FIRST_RUN: 'first_run',
};

export function labelFor(classification) {
  return {
    LIVE_OK: 'Live verified',
    STALE: 'Stale — preserving last good data',
    BLOCKED: 'Blocked (bot protection)',
    BLOCKED_TEMPORARY: 'Blocked — retry with same session',
    BLOCKED_HARD: 'Blocked — manual unlock required',
    PARSE_FAILED: 'Parse failed',
    PARSE_ISSUE: 'Schedule parse issue',
    RETRY_REQUIRED: 'Render incomplete — retry scheduled',
    SEASONAL_ONLY: 'Seasonal / hours only',
    OPEN_HOURS_ONLY: 'Open hours only',
    CONFIRMED_EMPTY: 'Confirmed empty (post-render)',
    EMPTY_BUT_EXPECTED_SCHEDULES: 'Expected schedules — awaiting retry',
    NO_SCHEDULE_DATA: 'No schedule data yet',
    FIXTURE_ONLY: 'Fixture data only',
  }[classification] ?? classification;
}

export function classificationForScheduleMode(scheduleMode, facilityType) {
  const type = (facilityType || '').toUpperCase();
  if (scheduleMode === 'OPEN_HOURS_ONLY' || type.includes('WADING') || type.includes('SPLASH')) {
    return Classification.OPEN_HOURS_ONLY;
  }
  if (scheduleMode === 'SEASONAL_ONLY' || type.includes('OUTDOOR')) {
    return Classification.SEASONAL_ONLY;
  }
  return Classification.NO_SCHEDULE_DATA;
}
