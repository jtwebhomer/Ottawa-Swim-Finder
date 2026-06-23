import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';

let db;

export function getDb(dbPath) {
  if (db) return db;
  const dir = path.dirname(dbPath);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  db = new Database(dbPath);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  initSchema(db);
  return db;
}

function initSchema(database) {
  database.exec(`
    CREATE TABLE IF NOT EXISTS facilities (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      address TEXT,
      lat REAL,
      lng REAL,
      type TEXT NOT NULL,
      schedule_mode TEXT NOT NULL DEFAULT 'HAS_SWIM_SCHEDULE',
      data_model TEXT,
      has_swim_schedule INTEGER NOT NULL DEFAULT 0,
      display_status TEXT,
      metadata_json TEXT,
      region TEXT,
      url TEXT,
      last_verified INTEGER,
      last_updated INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS schedules (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      facility_id TEXT NOT NULL,
      date TEXT,
      start_time TEXT NOT NULL,
      end_time TEXT NOT NULL,
      activity_type TEXT NOT NULL,
      raw_category TEXT,
      schedule_type TEXT NOT NULL DEFAULT 'expanded',
      day_of_week INTEGER,
      date_range_start TEXT,
      date_range_end TEXT,
      recurrence_pattern TEXT,
      source TEXT NOT NULL DEFAULT 'backend_verified',
      source_status TEXT NOT NULL DEFAULT 'fixture',
      confidence_score REAL NOT NULL DEFAULT 1.0,
      last_updated INTEGER NOT NULL,
      FOREIGN KEY (facility_id) REFERENCES facilities(id)
    );

    CREATE INDEX IF NOT EXISTS idx_schedules_facility ON schedules(facility_id);
    CREATE INDEX IF NOT EXISTS idx_schedules_date ON schedules(date);

    CREATE TABLE IF NOT EXISTS sync_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      timestamp INTEGER NOT NULL,
      status TEXT NOT NULL,
      blocked_count INTEGER NOT NULL DEFAULT 0,
      parsed_count INTEGER NOT NULL DEFAULT 0,
      facilities_updated INTEGER NOT NULL DEFAULT 0,
      facilities_failed INTEGER NOT NULL DEFAULT 0,
      duration_ms INTEGER NOT NULL DEFAULT 0,
      message TEXT
    );

    CREATE TABLE IF NOT EXISTS blocked_facilities (
      facility_id TEXT PRIMARY KEY,
      facility_name TEXT NOT NULL,
      reason TEXT,
      blocked_at INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS facility_baselines (
      facility_id TEXT PRIMARY KEY,
      session_count INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL
    );

    CREATE TABLE IF NOT EXISTS facility_scrape_diagnostics (
      facility_id TEXT PRIMARY KEY,
      classification TEXT NOT NULL,
      data_source TEXT NOT NULL DEFAULT 'unknown',
      quality_score INTEGER NOT NULL DEFAULT 0,
      render_status TEXT,
      dom_ready INTEGER NOT NULL DEFAULT 0,
      blocked_detected INTEGER NOT NULL DEFAULT 0,
      tables_found_count INTEGER NOT NULL DEFAULT 0,
      parsed_sessions_count INTEGER NOT NULL DEFAULT 0,
      display_status TEXT,
      confidence_score REAL NOT NULL DEFAULT 0,
      url TEXT,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (facility_id) REFERENCES facilities(id)
    );
  `);

  migrateSchema(database);
}

function migrateSchema(database) {
  const scheduleCols = database.prepare('PRAGMA table_info(schedules)').all();
  if (!scheduleCols.some((c) => c.name === 'source_status')) {
    database.exec(
      `ALTER TABLE schedules ADD COLUMN source_status TEXT NOT NULL DEFAULT 'fixture'`,
    );
  }
  if (!scheduleCols.some((c) => c.name === 'data_source')) {
    database.exec(
      `ALTER TABLE schedules ADD COLUMN data_source TEXT NOT NULL DEFAULT 'unknown'`,
    );
    database.exec(`UPDATE schedules SET data_source = source_status WHERE data_source = 'unknown'`);
  }

  const diagCols = database.prepare('PRAGMA table_info(facility_scrape_diagnostics)').all();
  if (diagCols.length > 0 && !diagCols.some((c) => c.name === 'quality_score')) {
    database.exec(
      `ALTER TABLE facility_scrape_diagnostics ADD COLUMN quality_score INTEGER NOT NULL DEFAULT 0`,
    );
  }

  const logCols = database.prepare('PRAGMA table_info(sync_logs)').all();
  if (logCols.length > 0 && !logCols.some((c) => c.name === 'sync_type')) {
    database.exec(`ALTER TABLE sync_logs ADD COLUMN sync_type TEXT NOT NULL DEFAULT 'manual'`);
  }
  if (logCols.length > 0 && !logCols.some((c) => c.name === 'stale_count')) {
    database.exec(`ALTER TABLE sync_logs ADD COLUMN stale_count INTEGER NOT NULL DEFAULT 0`);
  }

  const facCols = database.prepare('PRAGMA table_info(facilities)').all();
  if (facCols.length > 0 && !facCols.some((c) => c.name === 'data_model')) {
    database.exec(`ALTER TABLE facilities ADD COLUMN data_model TEXT`);
  }
  if (facCols.length > 0 && !facCols.some((c) => c.name === 'has_swim_schedule')) {
    database.exec(`ALTER TABLE facilities ADD COLUMN has_swim_schedule INTEGER NOT NULL DEFAULT 0`);
  }
  if (facCols.length > 0 && !facCols.some((c) => c.name === 'display_status')) {
    database.exec(`ALTER TABLE facilities ADD COLUMN display_status TEXT`);
  }
  if (facCols.length > 0 && !facCols.some((c) => c.name === 'metadata_json')) {
    database.exec(`ALTER TABLE facilities ADD COLUMN metadata_json TEXT`);
  }

  const diagCols2 = database.prepare('PRAGMA table_info(facility_scrape_diagnostics)').all();
  if (diagCols2.length > 0 && !diagCols2.some((c) => c.name === 'display_status')) {
    database.exec(`ALTER TABLE facility_scrape_diagnostics ADD COLUMN display_status TEXT`);
  }
  if (diagCols2.length > 0 && !diagCols2.some((c) => c.name === 'confidence_score')) {
    database.exec(`ALTER TABLE facility_scrape_diagnostics ADD COLUMN confidence_score REAL NOT NULL DEFAULT 0`);
  }
}

export function mapSourceStatus(source) {
  if (source === 'live' || source === 'backend_verified') return 'live';
  if (source === 'fixture') return 'fixture';
  return 'cached';
}

export function countAllSchedules(database) {
  return database.prepare('SELECT COUNT(*) as c FROM schedules').get().c;
}

export function isDatabaseEmpty(database) {
  return countAllSchedules(database) === 0;
}

export function recordBlockedFacility(database, facilityId, facilityName, reason) {
  database
    .prepare(
      `INSERT INTO blocked_facilities (facility_id, facility_name, reason, blocked_at)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(facility_id) DO UPDATE SET
         facility_name = excluded.facility_name,
         reason = excluded.reason,
         blocked_at = excluded.blocked_at`,
    )
    .run(facilityId, facilityName, reason, Date.now());
}

export function clearBlockedFacilities(database) {
  database.prepare('DELETE FROM blocked_facilities').run();
}

export function getBlockedFacilities(database) {
  return database
    .prepare('SELECT facility_id, facility_name, reason, blocked_at FROM blocked_facilities ORDER BY facility_name')
    .all();
}

export function upsertScrapeDiagnostic(database, facilityId, diag) {
  database
    .prepare(
      `INSERT INTO facility_scrape_diagnostics (
         facility_id, classification, data_source, quality_score, render_status,
         dom_ready, blocked_detected, tables_found_count, parsed_sessions_count,
         display_status, confidence_score, url, updated_at
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(facility_id) DO UPDATE SET
         classification = excluded.classification,
         data_source = excluded.data_source,
         quality_score = excluded.quality_score,
         render_status = excluded.render_status,
         dom_ready = excluded.dom_ready,
         blocked_detected = excluded.blocked_detected,
         tables_found_count = excluded.tables_found_count,
         parsed_sessions_count = excluded.parsed_sessions_count,
         display_status = excluded.display_status,
         confidence_score = excluded.confidence_score,
         url = excluded.url,
         updated_at = excluded.updated_at`,
    )
    .run(
      facilityId,
      diag.classification,
      diag.data_source ?? 'unknown',
      diag.quality_score ?? 0,
      diag.render_status ?? null,
      diag.dom_ready ?? 0,
      diag.blocked_detected ?? 0,
      diag.tables_found_count ?? 0,
      diag.parsed_sessions_count ?? 0,
      diag.display_status ?? diag.classification ?? null,
      diag.confidence_score ?? 0,
      diag.url ?? null,
      Date.now(),
    );
}

export function upsertFacilityMetadata(database, facilityId, metadata) {
  database
    .prepare('UPDATE facilities SET metadata_json = ?, last_updated = ? WHERE id = ?')
    .run(JSON.stringify(metadata), Date.now(), facilityId);
}

export function getFacilityDataCounts(database, facilityId) {
  const counts = database
    .prepare(
      `SELECT
         COUNT(*) AS total_count,
         SUM(CASE WHEN data_source = 'live' THEN 1 ELSE 0 END) AS live_count,
         SUM(CASE WHEN data_source = 'fixture' THEN 1 ELSE 0 END) AS fixture_count,
         SUM(CASE WHEN data_source = 'cached' THEN 1 ELSE 0 END) AS cached_count
       FROM schedules WHERE facility_id = ?`,
    )
    .get(facilityId);
  const diag = database
    .prepare(
      'SELECT classification, data_source FROM facility_scrape_diagnostics WHERE facility_id = ?',
    )
    .get(facilityId);
  return {
    totalCount: counts?.total_count ?? 0,
    liveCount: counts?.live_count ?? 0,
    fixtureCount: counts?.fixture_count ?? 0,
    cachedCount: counts?.cached_count ?? 0,
    classification: diag?.classification ?? null,
    dataSource: diag?.data_source ?? null,
  };
}

export function getRepairTargetFacilities(database) {
  return database
    .prepare(
      `SELECT f.id, f.name, f.type, f.schedule_mode, f.data_model, f.has_swim_schedule, f.display_status
       FROM facilities f
       LEFT JOIN facility_scrape_diagnostics d ON d.facility_id = f.id
       WHERE f.has_swim_schedule = 1
         AND (
           d.classification IN ('BLOCKED_TEMPORARY', 'PARSE_FAILED', 'PARSE_ISSUE', 'RETRY_REQUIRED')
           OR (f.display_status = 'PARSE_ISSUE' AND COALESCE(d.classification, '') != 'BLOCKED_HARD')
         )
       ORDER BY f.name`,
    )
    .all();
}

export function countFacilities(database) {
  return database.prepare('SELECT COUNT(*) as c FROM facilities').get().c;
}

export function insertSyncLog(database, {
  timestamp,
  syncType,
  status,
  blocked,
  parsedTotal,
  updated,
  failed,
  stale,
  durationMs,
  message,
}) {
  database
    .prepare(
      `INSERT INTO sync_logs (
         timestamp, sync_type, status, blocked_count, parsed_count,
         facilities_updated, facilities_failed, stale_count, duration_ms, message
       ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .run(timestamp, syncType, status, blocked, parsedTotal, updated, failed, stale ?? 0, durationMs, message);
}

export function recordSeasonalFacility(database, facilityId, classification) {
  upsertScrapeDiagnostic(database, facilityId, {
    classification,
    data_source: 'unknown',
    render_status: 'N/A',
    parsed_sessions_count: 0,
  });
}

export function getScrapeDiagnostics(database) {
  return database
    .prepare('SELECT * FROM facility_scrape_diagnostics ORDER BY facility_id')
    .all();
}

export function replaceSchedulesForFacility(database, facilityId, rows) {
  const deleteStmt = database.prepare(
    'DELETE FROM schedules WHERE facility_id = ?',
  );
  const insertStmt = database.prepare(`
    INSERT INTO schedules (
      facility_id, date, start_time, end_time, activity_type, raw_category,
      schedule_type, day_of_week, date_range_start, date_range_end,
      recurrence_pattern, source, source_status, data_source, confidence_score, last_updated
    ) VALUES (
      @facility_id, @date, @start_time, @end_time, @activity_type, @raw_category,
      @schedule_type, @day_of_week, @date_range_start, @date_range_end,
      @recurrence_pattern, @source, @source_status, @data_source, @confidence_score, @last_updated
    )
  `);

  const tx = database.transaction((entries) => {
    deleteStmt.run(facilityId);
    for (const row of entries) {
      insertStmt.run({
        ...row,
        data_source: row.data_source ?? row.source_status ?? 'unknown',
      });
    }
  });
  tx(rows);
}

export function getFacilityBaseline(database, facilityId) {
  return database
    .prepare('SELECT session_count FROM facility_baselines WHERE facility_id = ?')
    .get(facilityId)?.session_count ?? 0;
}

export function setFacilityBaseline(database, facilityId, count) {
  database
    .prepare(
      `INSERT INTO facility_baselines (facility_id, session_count, updated_at)
       VALUES (?, ?, ?)
       ON CONFLICT(facility_id) DO UPDATE SET
         session_count = excluded.session_count,
         updated_at = excluded.updated_at`,
    )
    .run(facilityId, count, Date.now());
}

export function closeDb() {
  if (db) {
    db.close();
    db = null;
  }
}
