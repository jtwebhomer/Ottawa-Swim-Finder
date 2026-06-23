/**
 * Stateful Playwright session — one browser, one context, persisted cookies/storage.
 */
import fs from 'fs';
import path from 'path';
import readline from 'readline';
import { fileURLToPath } from 'url';
import { chromium } from 'playwright';
import { runSinglePassPipeline } from './pageRenderer.js';
import { validateRenderedPage } from './renderValidation.js';
import { RenderStatus } from './classification.js';
import { facilityUrl } from './facilityUrls.js';
import { resolveHeadless, isInteractiveSyncMode, facilityDebugUrl } from './syncConfig.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const STATE_DIR = path.resolve(__dirname, '../state');
export const STATE_FILE = path.join(STATE_DIR, 'playwright-state.json');

const USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

let browser = null;
let context = null;
let activePage = null;

const sessionMeta = {
  loadedFromState: false,
  statePath: STATE_FILE,
  contextReused: false,
  lastSavedAt: null,
  navigations: 0,
};

export function getSessionMeta() {
  return { ...sessionMeta, hasBrowser: Boolean(browser), hasContext: Boolean(context) };
}

function storageStateExists() {
  return fs.existsSync(STATE_FILE);
}

export function loadSessionState() {
  if (!storageStateExists()) {
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
  } catch {
    return null;
  }
}

export async function saveSessionState() {
  if (!context) return false;
  fs.mkdirSync(STATE_DIR, { recursive: true });
  await context.storageState({ path: STATE_FILE });
  sessionMeta.lastSavedAt = Date.now();
  console.log('[SESSION] Saved browser state → backend/state/playwright-state.json');
  return true;
}

async function createContext(browserInstance, { headless }) {
  const options = {
    userAgent: USER_AGENT,
    locale: 'en-CA',
    timezoneId: 'America/Toronto',
    viewport: { width: 1280, height: 900 },
  };

  if (storageStateExists()) {
    options.storageState = STATE_FILE;
    sessionMeta.loadedFromState = true;
    console.log('[SESSION] Loaded persistent browser state from playwright-state.json');
  } else {
    sessionMeta.loadedFromState = false;
    console.log('[SESSION] No saved state — creating fresh browser context');
  }

  const ctx = await browserInstance.newContext(options);
  sessionMeta.contextReused = sessionMeta.loadedFromState;
  return ctx;
}

/**
 * Launch browser once per sync job and reuse context across all facilities.
 */
export async function ensureBrowserSession({ headless = true } = {}) {
  const effectiveHeadless = resolveHeadless(headless);

  if (!browser) {
    browser = await chromium.launch({
      headless: effectiveHeadless,
      slowMo: isInteractiveSyncMode() ? 40 : 0,
    });
  }

  if (!context) {
    context = await createContext(browser, { headless: effectiveHeadless });
  }

  if (!activePage || activePage.isClosed()) {
    activePage = await context.newPage();
  }

  return { browser, context, page: activePage };
}

export async function closeBrowserSession() {
  try {
    await saveSessionState();
  } catch (e) {
    console.warn('[SESSION] Failed to save state on close:', e.message);
  }

  if (activePage && !activePage.isClosed()) {
    await activePage.close().catch(() => {});
  }
  activePage = null;

  if (context) {
    await context.close().catch(() => {});
    context = null;
  }

  if (browser) {
    await browser.close().catch(() => {});
    browser = null;
  }
}

/** @deprecated alias */
export const launchBrowser = ensureBrowserSession;
export const startBrowserSession = ensureBrowserSession;

function packagePageResult(render, httpStatus = 0) {
  const validation = render.validation ?? validateRenderedPage(render.html ?? '');
  const blocked = validation.blocked || httpStatus === 403;
  return {
    html: render.html ?? '',
    domSize: (render.html ?? '').length,
    scheduleTableCount: render.tablesFound ?? validation.tablesFound ?? 0,
    challenge: blocked,
    blocked,
    httpStatus,
    status: blocked ? 'blocked' : render.renderStatus,
    renderStatus: blocked ? RenderStatus.BLOCKED : render.renderStatus,
    domReady: render.domReady ?? validation.domReady,
    validation,
    stable: render.stable,
    page: activePage,
  };
}

/**
 * Navigate using the shared session page — no per-facility contexts.
 */
export async function fetchFacilityInSession(url, { facilityId = 'unknown', headless = true } = {}) {
  const { page } = await ensureBrowserSession({ headless });

  const response = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
  const httpStatus = response?.status() ?? 0;
  sessionMeta.navigations++;

  let render = await runSinglePassPipeline(page);

  if (httpStatus === 403) {
    render = {
      ...render,
      renderStatus: RenderStatus.BLOCKED,
      blockedDetected: true,
      validation: { ...render.validation, blocked: true, reason: 'http_403' },
    };
  }

  await saveSessionState();

  return packagePageResult(render, httpStatus);
}

/**
 * Debug route handler — navigates shared session to facility (headed if interactive).
 */
export async function openFacilityDebugPage(facilityId) {
  const url = facilityUrl(facilityId);
  await ensureBrowserSession({ headless: false });
  const result = await fetchFacilityInSession(url, { facilityId, headless: false });
  return {
    facilityId,
    url,
    httpStatus: result.httpStatus,
    renderStatus: result.renderStatus,
    blocked: result.blocked,
    domSize: result.domSize,
    tablesFound: result.scheduleTableCount,
    title: await activePage.title().catch(() => ''),
  };
}

/**
 * Re-render and parse current page after manual challenge solve.
 */
export async function refreshCurrentPageAfterManualUnlock() {
  if (!activePage || activePage.isClosed()) {
    throw new Error('No active Playwright page — start a sync or open a debug URL first');
  }
  const render = await runSinglePassPipeline(activePage);
  await saveSessionState();
  return packagePageResult(render, 0);
}

export async function waitForManualUnlock(facilityId, facilityName = facilityId) {
  const link = facilityDebugUrl(facilityId);
  console.log('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('BLOCKED DETECTED (manual unlock required)');
  console.log(`Facility: ${facilityName}`);
  console.log(`Open debug page: ${link}`);
  console.log('Solve the challenge in the browser, then press ENTER here to continue…');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

  await ensureBrowserSession({ headless: false });
  await fetchFacilityInSession(facilityUrl(facilityId), { facilityId, headless: false });

  await new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    rl.question('', () => {
      rl.close();
      resolve();
    });
  });

  console.log(`[SESSION] Manual unlock acknowledged for ${facilityId} — re-parsing…`);
  return refreshCurrentPageAfterManualUnlock();
}

export function getActivePage() {
  return activePage;
}
