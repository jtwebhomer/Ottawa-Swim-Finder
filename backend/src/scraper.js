import { logScrapeDiagnostic } from './scrapeDebug.js';
import { RenderStatus } from './classification.js';
import { httpFetchFacilityPage } from './httpFetcher.js';

export { facilityUrl, randomFacilityDelayMs } from './facilityUrls.js';

/**
 * One facility, one HTTP fetch. Retries belong in the orchestrator.
 */
export async function fetchFacilityPageOnce(url, { facilityId = 'unknown' } = {}) {
  try {
    const result = await httpFetchFacilityPage(url);

    logScrapeDiagnostic({
      facility_id: facilityId,
      url,
      render_status: result.renderStatus,
      dom_ready: result.domReady,
      blocked_detected: result.blocked,
      tables_found_count: result.scheduleTableCount,
      http_status: result.httpStatus,
    });

    return result;
  } catch (err) {
    logScrapeDiagnostic({
      facility_id: facilityId,
      url,
      render_status: RenderStatus.ERROR,
      error: err.message,
    });
    throw err;
  }
}

/** @deprecated use fetchFacilityPageOnce */
export const fetchFacilityPage = fetchFacilityPageOnce;

/** No-op — kept for compatibility with older sync callers. */
export async function ensureBrowserSession() {
  return {};
}

/** No-op — kept for compatibility with older sync callers. */
export async function closeBrowserSession() {}
