import { DisplayStatus } from '../facilityRegistry.js';
import { parseScheduleHtml } from '../parser.js';
import { fetchFacilityPageOnce, facilityUrl } from '../scraper.js';
import { logScrapeDiagnostic } from '../scrapeDebug.js';
import { isChallengeHtml } from '../renderValidation.js';

/**
 * Pipeline A — swim schedule scraper (HTTP fetch, single pass).
 */
export async function runSwimSchedulePass(facilityId) {
  const url = facilityUrl(facilityId);
  const page = await fetchFacilityPageOnce(url, { facilityId });

  const parseResult = parseScheduleHtml(page.html, facilityId);
  const blocked =
    page.httpStatus === 403 ||
    (isChallengeHtml(page.html) && parseResult.sessions.length === 0);

  logScrapeDiagnostic({
    facility_id: facilityId,
    url,
    render_status: page.renderStatus,
    dom_ready: page.domReady,
    blocked_detected: blocked,
    tables_found_count: parseResult.tablesFound,
    parsed_sessions_count: parseResult.sessions.length,
    pipeline: 'swim_schedule',
  });

  return {
    page,
    parseResult,
    blocked,
    renderStatus: page.renderStatus,
    url,
    capturedAt: Date.now(),
    sourceType: 'live',
  };
}
