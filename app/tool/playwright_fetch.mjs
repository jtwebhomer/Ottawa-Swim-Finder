/**
 * One-shot Playwright fetch (legacy / fallback when no session server).
 * Usage: node tool/playwright_fetch.mjs <url>
 * Prints one JSON line: { status, finalUrl, html, domSize, scheduleTableCount, loadTimeMs }
 */
import { chromium } from 'playwright';
import { extractFacilityPage } from './playwright_page_extract.mjs';

const url = process.argv[2];
if (!url) {
  console.error('Usage: node tool/playwright_fetch.mjs <url>');
  process.exit(1);
}

const browser = await chromium.launch({ headless: true });
const context = await browser.newContext({
  userAgent:
    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
  locale: 'en-CA',
});
const page = await context.newPage();

try {
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });
  const result = await extractFacilityPage(page, { timeoutMs: 30000 });
  const payload = {
    status: result.status === 'ok' ? 200 : result.status === 'blocked' ? 403 : 0,
    finalUrl: result.finalUrl,
    html: result.html,
    domSize: result.domSize,
    scheduleTableCount: result.scheduleTableCount,
    loadTimeMs: result.loadTimeMs,
    expandedCount: result.expandedCount,
  };
  console.log(JSON.stringify(payload));
} finally {
  await browser.close();
}
