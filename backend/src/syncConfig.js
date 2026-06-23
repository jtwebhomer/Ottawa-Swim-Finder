/**
 * Sync runtime configuration.
 */
import { facilityUrl } from './facilityUrls.js';

export function logFacilityResult(facilityId, name, outcome) {
  const { status, blockClass, facilityUrl: pageUrl, dataSource } = outcome;
  const label = blockClass ? `${status} (${blockClass})` : status;
  const src = dataSource ? ` via ${dataSource}` : '';
  console.log(`[FACILITY] ${name} → ${label}${src}`);
  if (pageUrl) {
    console.log(`[FACILITY PAGE] ${pageUrl}`);
  }
}

/** @deprecated use facilityUrl() — kept for older log callers */
export function facilityPageUrl(facilityId) {
  return facilityUrl(facilityId);
}
