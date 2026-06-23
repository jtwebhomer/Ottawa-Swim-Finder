import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEBUG_DIR = path.join(__dirname, '..', 'data', 'debug');

export function ensureDebugDir() {
  if (!fs.existsSync(DEBUG_DIR)) fs.mkdirSync(DEBUG_DIR, { recursive: true });
}

export function logScrapeDiagnostic(diag) {
  const line = JSON.stringify({
    ts: new Date().toISOString(),
    ...diag,
  });
  console.log(`[scrape] ${line}`);
}

export function saveDebugArtifacts(facilityId, { html, screenshotBuffer, reason }) {
  if (process.env.SCRAPE_DEBUG !== 'true' && !process.env.SCRAPE_DEBUG) return;
  ensureDebugDir();
  const stamp = Date.now();
  if (html) {
    fs.writeFileSync(
      path.join(DEBUG_DIR, `${facilityId}_${stamp}.html`),
      html,
      'utf8',
    );
  }
  if (screenshotBuffer) {
    fs.writeFileSync(
      path.join(DEBUG_DIR, `${facilityId}_${stamp}.png`),
      screenshotBuffer,
    );
  }
  if (reason) {
    fs.appendFileSync(
      path.join(DEBUG_DIR, 'failures.log'),
      `${new Date().toISOString()} ${facilityId} ${reason}\n`,
    );
  }
}

export function saveFailureSnapshot(facilityId, html, reason) {
  ensureDebugDir();
  const file = path.join(DEBUG_DIR, `${facilityId}_latest.html`);
  fs.writeFileSync(file, html ?? '', 'utf8');
  fs.appendFileSync(
    path.join(DEBUG_DIR, 'failures.log'),
    `${new Date().toISOString()} ${facilityId} ${reason}\n`,
  );
}
