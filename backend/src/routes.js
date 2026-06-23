import express from 'express';
import { countAllSchedules, getBlockedFacilities } from './db.js';
import { mapSourceStatus } from './syncService.js';
import { ottawaTodayIso, ottawaDayOfWeek } from './ottawaTime.js';
import { isSyncRunning, runSyncJob } from './syncRunner.js';
import { FACILITY_STATUS_SQL, mapFacilityRowToApi } from './facilityStatusApi.js';
import { buildDebugAction } from './debugActions.js';
import {
  getCacheDir,
  listCacheFiles,
  loadBestCacheForFacility,
} from './cacheImport.js';

export function createRouter(database, { runFullSync, runRepairSync, syncOptions } = {}) {
  const router = express.Router();

  router.get('/health', (_req, res) => {
    res.json({ ok: true, timestamp: Date.now(), sync_running: isSyncRunning() });
  });

  router.get('/facilities', (_req, res) => {
    const rows = database.prepare(FACILITY_STATUS_SQL).all();
    const facilities = rows.map((f) => {
      const mapped = mapFacilityRowToApi(f);
      return {
        id: mapped.id,
        facility_id: mapped.facility_id,
        name: mapped.name,
        address: f.address ?? null,
        type: mapped.type,
        facility_type: mapped.facility_type,
        lat: f.lat ?? null,
        lng: f.lng ?? null,
        schedule_mode: mapped.schedule_mode,
        data_model: mapped.data_model,
        has_swim_schedule: mapped.has_swim_schedule,
        display_status: mapped.display_status,
        status: mapped.status,
        sessions_count: mapped.sessions_count,
        session_count: mapped.session_count,
        region: mapped.region,
        debug: mapped.debug,
      };
    });

    res.json({ facilities, total: facilities.length });
  });

  router.get('/schedules', (req, res) => {
    const facilityId = req.query.facility_id;
    if (!facilityId) {
      return res.status(400).json({ error: 'facility_id required' });
    }

    const facility = database
      .prepare('SELECT id, name, last_verified, last_updated FROM facilities WHERE id = ?')
      .get(facilityId);
    if (!facility) {
      return res.status(404).json({ error: 'facility not found' });
    }

    const rows = database
      .prepare(
        `SELECT date, start_time, end_time, activity_type, raw_category,
                source, source_status, day_of_week, recurrence_pattern, last_updated
         FROM schedules WHERE facility_id = ? ORDER BY date, start_time`,
      )
      .all(facilityId);

    res.json({
      facility_id: facilityId,
      facility_name: facility.name,
      schedules: rows.map((s) => ({
        date: s.date,
        start_time: s.start_time,
        end_time: s.end_time,
        activity_type: s.activity_type,
        raw_category: s.raw_category,
        source_status: s.source_status ?? mapSourceStatus(s.source),
        data_source: s.data_source ?? s.source_status ?? 'unknown',
      })),
    });
  });

  router.get('/swims/today', (_req, res) => {
    const today = ottawaTodayIso();
    const dow = ottawaDayOfWeek();

    const facilities = database
      .prepare(`SELECT id, name, type, lat, lng FROM facilities ORDER BY name`)
      .all();

    const byFacility = [];

    for (const facility of facilities) {
      const rows = database
        .prepare(
          `SELECT date, start_time, end_time, activity_type, raw_category, source_status, source
           FROM schedules
           WHERE facility_id = ?
             AND (date = ? OR (date IS NULL AND day_of_week = ?))
           ORDER BY start_time`,
        )
        .all(facility.id, today, dow);

      if (rows.length === 0) continue;

      byFacility.push({
        facility_id: facility.id,
        facility_name: facility.name,
        type: mapFacilityType(facility.type),
        lat: facility.lat,
        lng: facility.lng,
        swims: rows.map((s) => ({
          date: s.date ?? today,
          start_time: s.start_time,
          end_time: s.end_time,
          activity_type: s.activity_type,
          raw_category: s.raw_category,
          source_status: s.source_status ?? mapSourceStatus(s.source),
          data_source: s.data_source ?? s.source_status ?? 'unknown',
        })),
      });
    }

    res.json({ date: today, facilities: byFacility });
  });

  router.get('/cache/status', (req, res) => {
    const facilityId = req.query.facility_id;
    if (facilityId) {
      const files = listCacheFiles(facilityId);
      const best = loadBestCacheForFacility(facilityId);
      return res.json({
        cache_dir: getCacheDir(),
        facility_id: facilityId,
        files: files.map((f) => ({ name: f.name, captured_at: f.capturedAt, source: f.source })),
        best: best
          ? {
              session_count: best.sessionCount,
              tables_found: best.tablesFound,
              captured_at: best.capturedAt,
              score: best.score,
            }
          : null,
      });
    }
    res.json({ cache_dir: getCacheDir() });
  });

  router.get('/sync/status', (_req, res) => {
    const lastLog = database
      .prepare('SELECT * FROM sync_logs ORDER BY timestamp DESC LIMIT 1')
      .get();

    const facilityStats = database
      .prepare(`SELECT COUNT(*) as total FROM facilities`)
      .get();

    const totalSessions = countAllSchedules(database);
    const blocked = getBlockedFacilities(database);
    const syncHealth = computeSyncHealth(lastLog, totalSessions);

    const allFacilities = database.prepare(FACILITY_STATUS_SQL).all().map(mapFacilityRowToApi);

    res.json({
      last_sync_time: lastLog?.timestamp ?? null,
      last_successful_sync:
        lastLog?.status === 'success' ? lastLog.timestamp : findLastSuccess(database),
      total_facilities: facilityStats.total,
      total_sessions: totalSessions,
      blocked_facilities: blocked.map((b) => ({
        id: b.facility_id,
        facility_id: b.facility_id,
        name: b.facility_name,
        reason: b.reason,
        blocked_at: b.blocked_at,
        debug: buildDebugAction({ id: b.facility_id, scrape_classification: 'BLOCKED', sync_status: 'blocked' }),
      })),
      facilities: allFacilities,
      sync_health: syncHealth,
      sync_running: isSyncRunning(),
      last_status: lastLog?.status ?? 'never',
      success_count: lastLog?.facilities_updated ?? 0,
      error_count: (lastLog?.facilities_failed ?? 0) + (lastLog?.blocked_count ?? 0),
      cache_dir: getCacheDir(),
    });
  });

  router.post('/sync/run', async (_req, res) => {
    if (!runFullSync) {
      return res.status(503).json({ error: 'Sync not configured' });
    }
    if (isSyncRunning()) {
      return res.status(409).json({ error: 'Sync already running' });
    }

    res.status(202).json({ message: 'Weekly full sync started', sync_running: true });

    runSyncJob(runFullSync, database, syncOptions, 'manual-weekly').catch((e) => {
      console.error('[sync] Manual weekly sync failed:', e);
    });
  });

  router.post('/sync/repair', async (_req, res) => {
    if (!runRepairSync) {
      return res.status(503).json({ error: 'Repair sync not configured' });
    }
    if (isSyncRunning()) {
      return res.status(409).json({ error: 'Sync already running' });
    }

    res.status(202).json({ message: 'Repair sync started', sync_running: true });

    runSyncJob(runRepairSync, database, syncOptions, 'manual-repair').catch((e) => {
      console.error('[sync] Manual repair sync failed:', e);
    });
  });

  return router;
}

function mapFacilityType(type) {
  const t = (type || '').toUpperCase();
  if (t.includes('SPLASH')) return 'splash';
  if (t.includes('OUTDOOR')) return 'outdoor';
  if (t.includes('WADING')) return 'wading';
  if (t.includes('WAVE')) return 'wave';
  return 'indoor';
}

function findLastSuccess(database) {
  const row = database
    .prepare(
      `SELECT timestamp FROM sync_logs WHERE status = 'success' ORDER BY timestamp DESC LIMIT 1`,
    )
    .get();
  return row?.timestamp ?? null;
}

function computeSyncHealth(lastLog, totalSessions) {
  if (!lastLog) return totalSessions > 0 ? 'seeded' : 'empty';
  if (lastLog.status === 'success') return 'healthy';
  if (lastLog.status === 'partial') return 'degraded';
  if (totalSessions > 0) return 'degraded';
  return 'unhealthy';
}
