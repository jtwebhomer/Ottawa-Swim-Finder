import { RenderStatus } from './classification.js';
import { validateRenderedPage } from './renderValidation.js';

const STABILITY_MS = 500;
const POST_NAV_DELAY_MS = 1500;
const SCHEDULE_SELECTORS = ['table', '[class*="schedule"]', '[id*="schedule"]', 'main', 'article'];

async function waitForContentShell(page) {
  for (const sel of SCHEDULE_SELECTORS) {
    try {
      await page.waitForSelector(sel, { timeout: 12000 });
      return true;
    } catch (_) {
      /* try next selector */
    }
  }
  return false;
}

async function waitForDomStability(page, settleMs = STABILITY_MS) {
  let lastLen = 0;
  let stableSince = Date.now();
  const deadline = Date.now() + 10000;

  while (Date.now() < deadline) {
    const len = await page.evaluate(() => document.body?.innerHTML?.length ?? 0);
    if (len === lastLen) {
      if (Date.now() - stableSince >= settleMs) return true;
    } else {
      lastLen = len;
      stableSince = Date.now();
    }
    await page.waitForTimeout(100);
  }
  return false;
}

async function expandAllInteractive(page) {
  await page.evaluate(() => {
    document.querySelectorAll('details:not([open])').forEach((el) => el.setAttribute('open', ''));
    document.querySelectorAll('[aria-expanded="false"]').forEach((el) => {
      try { el.click(); } catch (_) { /* ignore */ }
    });
    document.querySelectorAll('button, a, [role="button"]').forEach((el) => {
      const t = (el.textContent || '').toLowerCase();
      if (/show|expand|more|view all|see all|schedule/.test(t)) {
        try { el.click(); } catch (_) { /* ignore */ }
      }
    });
    document.querySelectorAll('select').forEach((sel) => {
      for (let i = 0; i < sel.options.length; i++) {
        sel.selectedIndex = i;
        sel.dispatchEvent(new Event('change', { bubbles: true }));
      }
    });
  });
}

async function slowScrollToBottom(page) {
  await page.evaluate(async () => {
    const delay = (ms) => new Promise((r) => setTimeout(r, ms));
    const step = Math.max(200, Math.floor(window.innerHeight * 0.6));
    let y = 0;
    const max = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
    while (y < max) {
      window.scrollTo(0, y);
      y += step;
      await delay(120);
    }
    window.scrollTo(0, 0);
  });
}

/**
 * Single-pass render pipeline — NO reloads, NO repeated navigation.
 * Caller must navigate to the URL before invoking this.
 */
export async function runSinglePassPipeline(page) {
  await page.waitForLoadState('networkidle', { timeout: 45000 }).catch(() => {});
  await waitForContentShell(page);
  await page.waitForTimeout(POST_NAV_DELAY_MS);
  await expandAllInteractive(page);
  await slowScrollToBottom(page);
  const stable = await waitForDomStability(page, STABILITY_MS);
  const html = await page.content();
  const validation = validateRenderedPage(html);

  const renderStatus = validation.blocked
    ? RenderStatus.BLOCKED
    : validation.valid
      ? RenderStatus.OK
      : stable
        ? RenderStatus.INCOMPLETE
        : RenderStatus.UNSTABLE;

  return {
    html,
    stable,
    validation,
    domReady: validation.domReady,
    blockedDetected: validation.blocked,
    tablesFound: validation.tablesFound ?? 0,
    renderStatus,
  };
}
