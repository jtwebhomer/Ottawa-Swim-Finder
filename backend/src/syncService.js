import { SyncType } from './classification.js';
import { syncRegistryToDatabase } from './facilityRegistry.js';
import {
  insertSyncLog,
  countFacilities,
  replaceSchedulesForFacility,
  setFacilityBaseline,
} from './db.js';
import { randomFacilityDelayMs } from './scraper.js';
import { processFacility } from './pipelines/pipelineOrchestrator.js';
import { getRepairTargetFacilities } from './db.js';
import { facilityUrl } from './facilityUrls.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '../..');

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function allowFixtureSeed() {
  return process.env.ALLOW_FIXTURE_SEED === 'true' || process.env.NODE_ENV === 'test';
}

export async function seedFromAssets(database) {
  const result = syncRegistryToDatabase(database);

  if (allowFixtureSeed()) {
    await seedFixtureSchedules(database, Date.now());
  }

  return { count: result.total };
}

async function seedFixtureSchedules(database, now) {
  const seedPath = path.join(ROOT, 'app/assets/schedule_seed.json');
  if (!fs.existsSync(seedPath)) return;

  const seed = JSON.parse(fs.readFileSync(seedPath, 'utf8'));
  const byFacility = {};
  for (const row of seed.schedules || []) {
    byFacility[row.facility_id] ??= [];
    byFacility[row.facility_id].push({
      facility_id: row.facility_id,
      date: row.date ?? null,
      start_time: row.start_time,
      end_time: row.end_time,
      activity_type: row.category,
      raw_category: row.raw_category ?? row.category,
      schedule_type: row.schedule_type ?? 'expanded',
      day_of_week: row.day_of_week ?? null,
      date_range_start: row.date_range_start ?? null,
      date_range_end: row.date_range_end ?? null,
      recurrence_pattern: null,
      source: 'fixture',
      source_status: 'fixture',
      data_source: 'fixture',
      confidence_score: 0.9,
      last_updated: seed.bundled_at_ms ?? now,
    });
  }

  for (const [facilityId, rows] of Object.entries(byFacility)) {
    const live = database.prepare("SELECT COUNT(*) c FROM schedules WHERE facility_id = ? AND data_source = 'live'").get(facilityId)?.c ?? 0;
    if (live > 0) continue;
    const total = database.prepare('SELECT COUNT(*) c FROM schedules WHERE facility_id = ?').get(facilityId)?.c ?? 0;
    if (total > 0) continue;
    replaceSchedulesForFacility(database, facilityId, rows);
    setFacilityBaseline(database, facilityId, rows.length);
  }
}

async function runSyncLoop(database, { syncType, weeklyRetries, facilityFilter }) {
  const started = Date.now();
  let updated = 0;
  let blocked = 0;
  let failed = 0;
  let stale = 0;
  let parsedTotal = 0;
  const blockedList = [];

  const facilities = facilityFilter(database);

  console.log('[sync] HTTP scraper mode — cache imports merged when newer/more complete');

  try {
    for (const facility of facilities) {
      try {
        const result = await processFacility(database, facility, { weeklyRetries });

        if (result.updated) {
          updated++;
          parsedTotal += result.parsedCount;
        } else if (result.stale) stale++;
        else if (result.blocked) {
          blocked++;
          blockedList.push({
            id: facility.id,
            name: facility.name,
            reason: result.blockClass ?? result.displayStatus,
            facility_url: facilityUrl(facility.id),
          });
        } else if (result.failed) {
          failed++;
          blockedList.push({
            id: facility.id,
            name: facility.name,
            reason: result.blockClass ?? result.displayStatus,
            facility_url: facilityUrl(facility.id),
          });
        }
      } catch (e) {
        failed++;
        blockedList.push({
          id: facility.id,
          name: facility.name,
          reason: e.message,
          facility_url: facilityUrl(facility.id),
        });
        console.error(`[sync] FAIL ${facility.id}:`, e.message);
      }
      await sleep(randomFacilityDelayMs());
    }
  } finally {
    // no browser session to close
  }

  const durationMs = Date.now() - started;
  const status = blocked > 0 && updated === 0 && stale === 0 ? 'failure' : blocked > 0 || failed > 0 ? 'partial' : 'success';
  const timestamp = Date.now();

  if (blockedList.length > 0) {
    console.log('\n[sync] Facilities needing attention — open facility page or use Chrome extension to cache:');
    for (const b of blockedList) {
      console.log(`  • ${b.name} (${b.reason})`);
      if (b.facility_url) console.log(`    ${b.facility_url}`);
    }
  }

  insertSyncLog(database, {
    timestamp,
    syncType,
    status,
    blocked,
    parsedTotal,
    updated,
    failed,
    stale,
    durationMs,
    message: `[${syncType}] updated=${updated} stale=${stale} blocked=${blocked} failed=${failed}`,
  });

  return {
    syncType,
    status,
    updated,
    blocked,
    failed,
    stale,
    parsedTotal,
    durationMs,
    facilityTotal: countFacilities(database),
    last_sync_time: timestamp,
    blocked_facilities: blockedList,
    success_count: updated,
    error_count: failed + blocked,
  };
}

export async function runWeeklyFullSync(database, options = {}) {
  console.log('[sync] Weekly full sync — HTTP fetch + cache merge');
  await seedFromAssets(database);
  return runSyncLoop(database, {
    ...options,
    syncType: SyncType.WEEKLY_FULL,
    weeklyRetries: true,
    facilityFilter: (db) => db.prepare('SELECT * FROM facilities ORDER BY name').all(),
  });
}

export async function runRepairSync(database, options = {}) {
  const targets = getRepairTargetFacilities(database);
  if (targets.length === 0) {
    return { syncType: SyncType.REPAIR, status: 'success', updated: 0, skipped: true, repair_targets: 0 };
  }
  console.log(`[sync] Repair sync — ${targets.length} targets`);
  return runSyncLoop(database, {
    ...options,
    syncType: SyncType.REPAIR,
    weeklyRetries: true,
    facilityFilter: () => targets,
  });
}

export async function runFullSync(database, options = {}) {
  return runWeeklyFullSync(database, options);
}

export function mapSourceStatus(source) {
  if (source === 'live' || source === 'backend_verified') return 'live';
  if (source === 'fixture') return 'fixture';
  if (source === 'cached') return 'cached';
  return 'unknown';
}

export { syncRegistryToDatabase } from './facilityRegistry.js';
