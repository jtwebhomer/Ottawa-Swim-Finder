/**
 * Playwright Tier-2 fetch for dev/CI tooling.
 * Usage: node tool/playwright_fetch.mjs <url>
 * Prints one JSON line: { status, finalUrl, html }
 */
import { chromium } from 'playwright';

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
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 45000 });

  for (let i = 0; i < 24; i++) {
    const ready = await page.evaluate(() => {
      const tables = document.querySelectorAll('table');
      for (const table of tables) {
        const cap = table.querySelector('caption');
        const title =
          (cap ? cap.textContent : '') ||
          (table.previousElementSibling
            ? table.previousElementSibling.textContent
            : '');
        if (
          title.toLowerCase().includes('swim') ||
          title.toLowerCase().includes('aquafit')
        ) {
          return true;
        }
      }
      const body = document.body ? document.body.innerHTML : '';
      return body.length > 8000 && !body.toLowerCase().includes('pardon our interruption');
    });
    if (ready) break;
    await page.waitForTimeout(500);
  }

  const html = await page.content();
  const payload = {
    status: 200,
    finalUrl: page.url(),
    html,
  };
  console.log(JSON.stringify(payload));
} finally {
  await browser.close();
}
