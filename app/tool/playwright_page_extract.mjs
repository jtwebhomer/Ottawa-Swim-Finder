/**
 * Shared DOM extraction for Ottawa facility schedule pages.
 * Used by playwright_fetch.mjs (one-shot) and playwright_sync_server.mjs (session).
 */

export const CHALLENGE_SIGNATURES = [
  'pardon our interruption',
  'access denied',
  'cloudflare',
  'captcha',
  'cf-browser-verification',
  'just a moment',
  'enable javascript and cookies',
];

export function isChallengeHtml(html) {
  const lower = (html || '').toLowerCase();
  return CHALLENGE_SIGNATURES.some((sig) => lower.includes(sig));
}

export function countScheduleTables(page) {
  return page.evaluate(() => {
    let count = 0;
    const tables = document.querySelectorAll('table');
    for (const table of tables) {
      const cap = table.querySelector('caption');
      const title =
        (cap ? cap.textContent : '') ||
        (table.previousElementSibling
          ? table.previousElementSibling.textContent
          : '');
      const t = (title || '').toLowerCase();
      if (t.includes('swim') || t.includes('aquafit') || t.includes('pool')) {
        count++;
      }
    }
    return count;
  });
}

export async function expandInteractiveSchedules(page) {
  return page.evaluate(async () => {
    let expanded = 0;

    const clickIfVisible = (el) => {
      if (!el || el.offsetParent === null) return false;
      try {
        el.click();
        return true;
      } catch (_) {
        return false;
      }
    };

    const selectors = [
      'details:not([open]) > summary',
      '[aria-expanded="false"]',
      'button[aria-expanded="false"]',
      '.accordion-button.collapsed',
      '.collapse-toggle',
      '[data-toggle="collapse"]',
      'a.show-more',
      'button.show-more',
    ];

    for (const sel of selectors) {
      const nodes = document.querySelectorAll(sel);
      for (const node of nodes) {
        const text = (node.textContent || '').toLowerCase();
        if (
          text.includes('schedule') ||
          text.includes('swim') ||
          text.includes('aquafit') ||
          text.includes('show') ||
          text.includes('more') ||
          sel.includes('accordion') ||
          sel.includes('collapse') ||
          sel.includes('details')
        ) {
          if (clickIfVisible(node)) expanded++;
        }
      }
    }

    const selects = document.querySelectorAll('select');
    for (const select of selects) {
      if (select.options && select.options.length > 1) {
        for (let i = 1; i < select.options.length; i++) {
          select.selectedIndex = i;
          select.dispatchEvent(new Event('change', { bubbles: true }));
          expanded++;
        }
        select.selectedIndex = 0;
        select.dispatchEvent(new Event('change', { bubbles: true }));
      }
    }

    await new Promise((r) => setTimeout(r, 300));
    return expanded;
  });
}

export async function waitForScheduleContent(page, { timeoutMs = 30000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const state = await page.evaluate(() => {
      const body = document.body ? document.body.innerHTML : '';
      const lower = body.toLowerCase();
      if (
        lower.includes('pardon our interruption') ||
        lower.includes('just a moment') ||
        lower.includes('cf-browser-verification')
      ) {
        return { ready: false, challenge: true, tables: 0, domSize: body.length };
      }

      let tables = 0;
      const tableNodes = document.querySelectorAll('table');
      for (const table of tableNodes) {
        const cap = table.querySelector('caption');
        const title =
          (cap ? cap.textContent : '') ||
          (table.previousElementSibling
            ? table.previousElementSibling.textContent
            : '');
        const t = (title || '').toLowerCase();
        if (t.includes('swim') || t.includes('aquafit') || t.includes('pool')) {
          tables++;
        }
      }

      const main =
        document.querySelector('main') ||
        document.querySelector('#main-content') ||
        document.querySelector('.layout-content');
      const mainSize = main ? main.innerHTML.length : 0;

      const ready =
        tables > 0 ||
        (body.length > 8000 && mainSize > 2000 && !lower.includes('access denied'));

      return { ready, challenge: false, tables, domSize: body.length };
    });

    if (state.challenge) return state;
    if (state.ready) return state;
    await page.waitForTimeout(500);
  }

  const finalState = await page.evaluate(() => ({
    ready: false,
    challenge: false,
    tables: document.querySelectorAll('table').length,
    domSize: document.body ? document.body.innerHTML.length : 0,
  }));
  return finalState;
}

export async function extractFacilityPage(page, { timeoutMs = 30000 } = {}) {
  const start = Date.now();
  await page.waitForLoadState('networkidle', { timeout: timeoutMs }).catch(() => {});

  const waitState = await waitForScheduleContent(page, { timeoutMs });
  const expandedCount = await expandInteractiveSchedules(page);
  await page.waitForTimeout(400);
  await waitForScheduleContent(page, { timeoutMs: 5000 });

  const html = await page.content();
  const domSize = html.length;
  const scheduleTableCount = await countScheduleTables(page);
  const loadTimeMs = Date.now() - start;
  const challenge = isChallengeHtml(html) || waitState.challenge;

  return {
    html,
    finalUrl: page.url(),
    domSize,
    scheduleTableCount,
    expandedCount,
    loadTimeMs,
    challenge,
    status: challenge ? 'blocked' : domSize < 500 ? 'empty' : 'ok',
  };
}
