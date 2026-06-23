import 'dotenv/config';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { getDb, closeDb } from './db.js';
import { listCacheFiles, loadBestCacheForFacility, getCacheDir } from './cacheImport.js';
import { resolveFacilityRecord } from './facilityRegistry.js';
import { applySwimWrite } from './pipelines/pipelineOrchestrator.js';
import { classifyScrapeOutcome } from './blockClassifier.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DB_PATH = path.resolve(
  process.env.DATABASE_PATH || path.join(__dirname, '../data/ottawa_swim.db'),
);

const db = getDb(DB_PATH);
const arg = process.argv[2];

if (arg === '--list') {
  const dir = getCacheDir();
  console.log(`Cache dir: ${dir}`);
  if (!fs.existsSync(dir)) {
    console.log('(empty — no cache files yet)');
    closeDb();
    process.exit(0);
  }
  const facilities = new Set();
  for (const name of fs.readdirSync(dir)) {
    if (name.endsWith('.html')) facilities.add(name.replace(/_\d+\.html$/, ''));
  }
  for (const id of facilities) {
    const best = loadBestCacheForFacility(id);
    console.log(`${id}: ${best?.sessionCount ?? 0} sessions (${listCacheFiles(id).length} files)`);
  }
  closeDb();
  process.exit(0);
}

const facilityId = arg;
if (!facilityId) {
  console.log('Usage: node src/cli-import-cache.js <facility-id|--list>');
  closeDb();
  process.exit(1);
}

const best = loadBestCacheForFacility(facilityId);
if (!best) {
  console.error(`No valid cache for ${facilityId}`);
  closeDb();
  process.exit(1);
}

const registry = resolveFacilityRecord({ id: facilityId });
const outcome = classifyScrapeOutcome({
  blocked: false,
  parseResult: best.parseResult,
  renderStatus: best.renderStatus,
  html: best.html,
  httpStatus: 200,
});

const result = applySwimWrite(db, registry, {
  page: { html: best.html, httpStatus: 200, domReady: true },
  parseResult: best.parseResult,
  outcome,
  sourceType: 'cached',
  blocked: false,
  renderStatus: best.renderStatus,
});

console.log(
  result.updated
    ? `Imported ${result.parsedCount} sessions for ${facilityId} (cached)`
    : `No DB update for ${facilityId} — existing data is newer or more complete`,
);

closeDb();
