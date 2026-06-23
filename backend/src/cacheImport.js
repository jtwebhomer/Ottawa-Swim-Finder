import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { parseScheduleHtml } from './parser.js';
import { validateRenderedPage, isChallengeHtml } from './renderValidation.js';
import { DisplayStatus } from './facilityRegistry.js';
import { RenderStatus } from './classification.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export function getCacheDir() {
  return process.env.CACHE_IMPORT_DIR || path.resolve(__dirname, '../data/cache');
}

export function ensureCacheDir() {
  const dir = getCacheDir();
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function parseCacheTimestamp(filename) {
  const match = filename.match(/_(\d+)\.html$/);
  return match ? Number(match[1]) : 0;
}

export function listCacheFiles(facilityId) {
  const dir = getCacheDir();
  if (!fs.existsSync(dir)) return [];

  return fs
    .readdirSync(dir)
    .filter((name) => name.startsWith(`${facilityId}_`) && name.endsWith('.html'))
    .map((name) => {
      const fullPath = path.join(dir, name);
      const capturedAt = parseCacheTimestamp(name);
      const metaPath = fullPath.replace(/\.html$/, '.json');
      let meta = {};
      if (fs.existsSync(metaPath)) {
        try {
          meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
        } catch {
          meta = {};
        }
      }
      return {
        name,
        path: fullPath,
        metaPath,
        capturedAt: meta.captured_at ?? capturedAt ?? fs.statSync(fullPath).mtimeMs,
        source: meta.source ?? 'unknown',
      };
    })
    .sort((a, b) => b.capturedAt - a.capturedAt);
}

export function scoreScheduleCandidate({ sessionCount, tablesFound, htmlLength, capturedAt }) {
  const ageMs = Math.max(0, Date.now() - (capturedAt ?? 0));
  const freshness = Math.max(0, 100 - ageMs / (24 * 60 * 60 * 1000));
  return (
    sessionCount * 100_000 +
    tablesFound * 1_000 +
    Math.min(htmlLength ?? 0, 50_000) / 10 +
    freshness
  );
}

export function evaluateCachedHtml(html, facilityId, capturedAt = Date.now()) {
  if (!html || html.length < 500) return null;
  if (isChallengeHtml(html)) return null;

  const validation = validateRenderedPage(html);
  if (validation.blocked) return null;

  const parseResult = parseScheduleHtml(html, facilityId);
  const sessionCount = parseResult.sessions.length;
  if (sessionCount === 0 && !validation.valid) return null;

  return {
    html,
    parseResult,
    validation,
    capturedAt,
    sessionCount,
    tablesFound: parseResult.tablesFound ?? validation.tablesFound ?? 0,
    score: scoreScheduleCandidate({
      sessionCount,
      tablesFound: parseResult.tablesFound ?? validation.tablesFound ?? 0,
      htmlLength: html.length,
      capturedAt,
    }),
    renderStatus: sessionCount > 0 ? RenderStatus.OK : RenderStatus.INCOMPLETE,
    blocked: false,
    httpStatus: 200,
    displayStatus: sessionCount > 0 ? DisplayStatus.LIVE_OK : DisplayStatus.PARSE_ISSUE,
  };
}

export function loadBestCacheForFacility(facilityId) {
  let best = null;
  for (const file of listCacheFiles(facilityId)) {
    const html = fs.readFileSync(file.path, 'utf8');
    const candidate = evaluateCachedHtml(html, facilityId, file.capturedAt);
    if (!candidate) continue;
    if (!best || candidate.score > best.score) {
      best = { ...candidate, file: file.path, source: file.source };
    }
  }
  return best;
}

/**
 * Pick the best schedule source — most complete first, then newest.
 */
export function pickBestScheduleSource(candidates) {
  const valid = candidates.filter((c) => c && c.sessionCount > 0);
  if (valid.length === 0) return null;

  return valid.sort((a, b) => {
    if (a.sessionCount !== b.sessionCount) return b.sessionCount - a.sessionCount;
    if (a.tablesFound !== b.tablesFound) return b.tablesFound - a.tablesFound;
    return (b.capturedAt ?? 0) - (a.capturedAt ?? 0);
  })[0];
}

export function saveCacheImport(facilityId, html, meta = {}) {
  ensureCacheDir();
  const capturedAt = meta.captured_at ?? Date.now();
  const filename = `${facilityId}_${capturedAt}.html`;
  const htmlPath = path.join(getCacheDir(), filename);
  const metaPath = htmlPath.replace(/\.html$/, '.json');

  fs.writeFileSync(htmlPath, html, 'utf8');
  fs.writeFileSync(
    metaPath,
    JSON.stringify(
      {
        facility_id: facilityId,
        captured_at: capturedAt,
        source: meta.source ?? 'extension',
        url: meta.url ?? null,
        session_count: meta.session_count ?? null,
        imported_at: Date.now(),
      },
      null,
      2,
    ),
    'utf8',
  );

  const evaluated = evaluateCachedHtml(html, facilityId, capturedAt);
  return {
    path: htmlPath,
    metaPath,
    capturedAt,
    evaluated,
  };
}

export function importAllCacheFiles(database, processFn) {
  const dir = getCacheDir();
  if (!fs.existsSync(dir)) return { imported: 0, facilities: [] };

  const byFacility = new Map();
  for (const name of fs.readdirSync(dir)) {
    if (!name.endsWith('.html')) continue;
    const facilityId = name.replace(/_\d+\.html$/, '');
    if (!facilityId) continue;
    byFacility.set(facilityId, facilityId);
  }

  const results = [];
  for (const facilityId of byFacility.keys()) {
    const best = loadBestCacheForFacility(facilityId);
    if (best && processFn) {
      results.push(processFn(database, facilityId, best));
    }
  }
  return { imported: results.filter(Boolean).length, facilities: results };
}
