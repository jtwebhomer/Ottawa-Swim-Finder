/**
 * Persistent Playwright sync server — reuses one Chromium instance per sync session.
 *
 * Protocol (stdin/stdout JSON lines):
 *   → {"cmd":"start","headless":true}
 *   ← {"type":"ready"}
 *   → {"cmd":"fetch","url":"...","facilityId":"...","timeoutMs":30000}
 *   ← {"type":"result",...}
 *   → {"cmd":"close"}
 *   ← {"type":"closed"}
 */
import readline from 'readline';
import { chromium } from 'playwright';
import { extractFacilityPage } from './playwright_page_extract.mjs';

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });

let browser = null;
let context = null;
let lastNavAt = 0;

const USER_AGENT =
  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

function send(obj) {
  process.stdout.write(`${JSON.stringify(obj)}\n`);
}

async function ensureBrowser(headless = true) {
  if (browser) return;
  browser = await chromium.launch({ headless });
  context = await browser.newContext({
    userAgent: USER_AGENT,
    locale: 'en-CA',
  });
}

async function fetchFacility({ url, facilityId, timeoutMs = 30000, retry = true }) {
  await ensureBrowser(true);
  const navDelay = 500 + Math.floor(Math.random() * 1000);
  const sinceLast = Date.now() - lastNavAt;
  if (sinceLast < navDelay) {
    await new Promise((r) => setTimeout(r, navDelay - sinceLast));
  }

  let page = null;
  try {
    page = await context.newPage();
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: timeoutMs });

    let result = await extractFacilityPage(page, { timeoutMs });

    if (result.status !== 'ok' && retry) {
      await page.close();
      page = await context.newPage();
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: timeoutMs });
      result = await extractFacilityPage(page, { timeoutMs });
    }

    lastNavAt = Date.now();

    return {
      type: 'result',
      facilityId,
      status: result.status,
      finalUrl: result.finalUrl,
      html: result.html,
      domSize: result.domSize,
      scheduleTableCount: result.scheduleTableCount,
      expandedCount: result.expandedCount,
      loadTimeMs: result.loadTimeMs,
      httpStatus: result.status === 'ok' ? 200 : result.status === 'blocked' ? 403 : 0,
    };
  } catch (e) {
    return {
      type: 'result',
      facilityId,
      status: 'error',
      error: String(e),
      httpStatus: 0,
      domSize: 0,
      scheduleTableCount: 0,
      loadTimeMs: 0,
    };
  } finally {
    if (page) {
      try {
        await page.close();
      } catch (_) {}
    }
  }
}

async function closeBrowser() {
  if (context) {
    try {
      await context.close();
    } catch (_) {}
    context = null;
  }
  if (browser) {
    try {
      await browser.close();
    } catch (_) {}
    browser = null;
  }
  send({ type: 'closed' });
}

rl.on('line', async (line) => {
  let msg;
  try {
    msg = JSON.parse(line);
  } catch (_) {
    send({ type: 'error', message: 'Invalid JSON' });
    return;
  }

  try {
    switch (msg.cmd) {
      case 'start':
        await ensureBrowser(msg.headless !== false);
        send({ type: 'ready' });
        break;
      case 'fetch':
        send(
          await fetchFacility({
            url: msg.url,
            facilityId: msg.facilityId,
            timeoutMs: msg.timeoutMs ?? 30000,
            retry: msg.retry !== false,
          }),
        );
        break;
      case 'close':
        await closeBrowser();
        rl.close();
        process.exit(0);
        break;
      default:
        send({ type: 'error', message: `Unknown cmd: ${msg.cmd}` });
    }
  } catch (e) {
    send({ type: 'error', message: String(e) });
  }
});

send({ type: 'listening' });
