import { RenderStatus } from './classification.js';
import {
  validateRenderedPage,
  isChallengeHtml,
  countSwimTablesInHtml,
} from './renderValidation.js';

export const STABLE_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/**
 * HTTP fetch for facility pages — no Playwright.
 */
export async function httpFetchFacilityPage(url) {
  const res = await fetch(url, {
    headers: {
      'User-Agent': STABLE_UA,
      Accept: 'text/html,application/xhtml+xml',
      'Accept-Language': 'en-CA,en;q=0.9',
    },
    redirect: 'follow',
  });

  const html = await res.text();
  const httpStatus = res.status;
  const validation = validateRenderedPage(html);
  const blocked =
    httpStatus === 403 ||
    validation.blocked ||
    (isChallengeHtml(html) && !validation.valid);

  let renderStatus = RenderStatus.OK;
  if (blocked) renderStatus = RenderStatus.BLOCKED;
  else if (!validation.valid) renderStatus = RenderStatus.INCOMPLETE;
  else if (!validation.domReady) renderStatus = RenderStatus.UNSTABLE;

  return {
    html,
    httpStatus,
    blocked,
    challenge: blocked,
    domReady: validation.domReady,
    renderStatus,
    scheduleTableCount: validation.tablesFound ?? countSwimTablesInHtml(html),
    validation,
    status: blocked ? 'blocked' : 'ok',
  };
}
