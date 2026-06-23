import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import { countAllSchedules, getBlockedFacilities } from './db.js';
import { isSyncRunning, getLastSyncResult } from './syncRunner.js';
import { FACILITY_STATUS_SQL, mapFacilityRowToApi } from './facilityStatusApi.js';
import { buildDebugAction } from './debugActions.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function localhostOnly(req, res, next) {
  const ip = req.socket?.remoteAddress ?? '';
  const ok =
    ip === '127.0.0.1' ||
    ip === '::1' ||
    ip === '::ffff:127.0.0.1' ||
    ip.endsWith('127.0.0.1');
  if (!ok) {
    return res.status(403).send('Sync Dashboard is only available on this PC (localhost).');
  }
  next();
}

export function createDashboardRouter(database) {
  const router = express.Router();
  const staticDir = path.join(__dirname, '../dashboard');

  router.use(localhostOnly);
  router.use(express.static(staticDir));

  router.get('/api/status', (_req, res) => {
    const lastLog = database
      .prepare('SELECT * FROM sync_logs ORDER BY timestamp DESC LIMIT 1')
      .get();

    const lastSuccess = database
      .prepare(
        `SELECT * FROM sync_logs WHERE status IN ('success', 'partial') ORDER BY timestamp DESC LIMIT 1`,
      )
      .get();

    const facilities = database.prepare(FACILITY_STATUS_SQL).all();
    const rows = facilities.map(mapFacilityRowToApi);

    const summary = {
      total: rows.length,
      live_verified: rows.filter((r) => r.sync_status === 'live').length,
      fixture: rows.filter((r) => r.sync_status === 'fixture').length,
      blocked: rows.filter((r) => r.sync_status === 'blocked').length,
      parse_failed: rows.filter((r) => r.sync_status === 'parse_failed').length,
      retry_required: rows.filter((r) => r.sync_status === 'retry_required').length,
      confirmed_empty: rows.filter((r) => r.sync_status === 'confirmed_empty').length,
      stale: rows.filter((r) => r.sync_status === 'stale').length,
      open_hours: rows.filter((r) => r.sync_status === 'open_hours').length,
      seasonal: rows.filter((r) => r.sync_status === 'seasonal').length,
      unknown: rows.filter((r) => r.sync_status === 'unknown').length,
      debug_eligible: rows.filter((r) => r.debug?.can_debug).length,
    };

    res.json({
      generated_at: Date.now(),
      sync_running: isSyncRunning(),
      last_run: lastLog
        ? {
            timestamp: lastLog.timestamp,
            sync_type: lastLog.sync_type,
            status: lastLog.status,
            updated: lastLog.facilities_updated,
            blocked: lastLog.blocked_count,
            failed: lastLog.facilities_failed,
            stale: lastLog.stale_count,
            sessions_parsed: lastLog.parsed_count,
            duration_ms: lastLog.duration_ms,
            message: lastLog.message,
          }
        : null,
      last_successful_sync: lastSuccess?.timestamp ?? null,
      last_successful_status: lastSuccess?.status ?? null,
      total_sessions: countAllSchedules(database),
      blocked_now: getBlockedFacilities(database).map((b) => ({
        id: b.facility_id,
        name: b.facility_name,
        reason: b.reason,
        blocked_at: b.blocked_at,
        debug: buildDebugAction({ id: b.facility_id, scrape_classification: 'BLOCKED', sync_status: 'blocked' }),
      })),
      in_memory_result: getLastSyncResult(),
      summary,
      facilities: rows,
    });
  });

  router.get('/', (_req, res) => {
    res.sendFile(path.join(staticDir, 'index.html'));
  });

  return router;
}
