/**
 * Server-side facility page links for broken facilities.
 */
import { Classification, RenderStatus } from './classification.js';
import { DisplayStatus } from './facilityRegistry.js';
import { facilityUrl } from './facilityUrls.js';

const DEBUG_REASON = {
  BOT_CHALLENGE: 'bot_challenge',
  PARSE_FAILED: 'parse_failed',
  RETRY_REQUIRED: 'retry_required',
  INCOMPLETE: 'incomplete',
};

const DEBUG_ELIGIBLE_CLASSIFICATIONS = new Set([
  Classification.BLOCKED,
  Classification.BLOCKED_HARD,
  Classification.BLOCKED_TEMPORARY,
  Classification.PARSE_FAILED,
  Classification.PARSE_ISSUE,
  Classification.RETRY_REQUIRED,
  Classification.EMPTY_BUT_EXPECTED_SCHEDULES,
  DisplayStatus.BLOCKED,
  DisplayStatus.PARSE_ISSUE,
]);

const NON_DEBUG_DATA_MODELS = new Set(['HOURS_ONLY', 'STATUS_ONLY']);
const NON_DEBUG_SCHEDULE_MODES = new Set(['OPEN_HOURS_ONLY']);

export function resolveDebugReason(facility) {
  const dataModel = (facility.data_model || '').toUpperCase();
  const scheduleMode = facility.schedule_mode || '';
  const facilityType = (facility.type || facility.facility_type || '').toUpperCase();
  const classification = facility.scrape_classification || facility.classification || '';
  const displayStatus = facility.display_status || '';
  const renderStatus = facility.render_status || '';
  const syncStatus = facility.sync_status || '';

  const isBrokenNonSwim =
    facility.blocked_detected ||
    classification === Classification.BLOCKED ||
    classification === Classification.BLOCKED_HARD ||
    displayStatus === DisplayStatus.BLOCKED;

  if (NON_DEBUG_DATA_MODELS.has(dataModel) && !isBrokenNonSwim) {
    return null;
  }
  if (
    NON_DEBUG_SCHEDULE_MODES.has(scheduleMode) &&
    !isBrokenNonSwim &&
    (facilityType.includes('WADING') || facilityType.includes('SPLASH'))
  ) {
    return null;
  }
  if (
    (classification === Classification.SEASONAL_ONLY ||
      scheduleMode === 'SEASONAL_ONLY' ||
      dataModel === 'MIXED_SEASONAL' ||
      dataModel === 'SEASONAL_HOURS') &&
    !isBrokenNonSwim &&
    syncStatus !== 'blocked' &&
    syncStatus !== 'parse_failed'
  ) {
    return null;
  }

  if (
    classification === Classification.BLOCKED ||
    classification === Classification.BLOCKED_HARD ||
    classification === Classification.BLOCKED_TEMPORARY ||
    displayStatus === DisplayStatus.BLOCKED ||
    syncStatus === 'blocked' ||
    facility.blocked_detected
  ) {
    return DEBUG_REASON.BOT_CHALLENGE;
  }

  if (
    classification === Classification.PARSE_FAILED ||
    classification === Classification.PARSE_ISSUE ||
    displayStatus === DisplayStatus.PARSE_ISSUE ||
    syncStatus === 'parse_failed'
  ) {
    return DEBUG_REASON.PARSE_FAILED;
  }

  if (
    classification === Classification.RETRY_REQUIRED ||
    classification === Classification.EMPTY_BUT_EXPECTED_SCHEDULES ||
    syncStatus === 'retry_required'
  ) {
    return DEBUG_REASON.RETRY_REQUIRED;
  }

  if (
    renderStatus === RenderStatus.INCOMPLETE ||
    renderStatus === RenderStatus.UNSTABLE ||
    renderStatus === RenderStatus.ERROR
  ) {
    return DEBUG_REASON.INCOMPLETE;
  }

  if (facility.blocked_reason && !NON_DEBUG_DATA_MODELS.has(dataModel)) {
    return DEBUG_REASON.BOT_CHALLENGE;
  }

  return null;
}

export function buildDebugAction(facility) {
  const reason = resolveDebugReason(facility);
  const canDebug = reason != null;
  const id = facility.id ?? facility.facility_id;

  return {
    can_debug: canDebug,
    debug_url: canDebug ? facilityUrl(id) : null,
    reason,
  };
}

export function isDebugEligibleClassification(classification) {
  return DEBUG_ELIGIBLE_CLASSIFICATIONS.has(classification);
}
