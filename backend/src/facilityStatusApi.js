/**
 * Maps DB facility rows → API payloads with status + debug metadata.
 */
import { Classification, labelFor, RenderStatus } from './classification.js';
import { DisplayStatus } from './facilityRegistry.js';
import { buildDebugAction } from './debugActions.js';

export function inferDataSource(f) {
  if (f.live_count > 0) return 'live';
  if (f.fixture_count > 0) return 'fixture';
  return f.data_source ?? 'unknown';
}

export function simplifyType(type) {
  const t = (type || '').toUpperCase();
  if (t.includes('SPLASH')) return 'splash';
  if (t.includes('OUTDOOR')) return 'outdoor';
  if (t.includes('WADING')) return 'wading';
  if (t.includes('WAVE')) return 'wave';
  return 'indoor';
}

export function deriveFacilityStatus(f) {
  const cls = f.scrape_classification ?? f.classification;
  const display = f.display_status;

  if (cls === Classification.STALE || display === DisplayStatus.STALE) {
    return { key: 'stale', label: labelFor(Classification.STALE) };
  }
  if (
    cls === Classification.OPEN_HOURS_ONLY ||
    f.schedule_mode === 'OPEN_HOURS_ONLY' ||
    display === DisplayStatus.HOURS_ONLY
  ) {
    return { key: 'open_hours', label: labelFor(Classification.OPEN_HOURS_ONLY) };
  }
  if (
    cls === Classification.SEASONAL_ONLY ||
    f.schedule_mode === 'SEASONAL_ONLY' ||
    display === DisplayStatus.SEASONAL
  ) {
    return { key: 'seasonal', label: labelFor(Classification.SEASONAL_ONLY) };
  }
  if (
    cls === Classification.BLOCKED ||
    cls === Classification.BLOCKED_HARD ||
    cls === Classification.BLOCKED_TEMPORARY ||
    display === DisplayStatus.BLOCKED ||
    f.blocked_detected
  ) {
    return { key: 'blocked', label: labelFor(cls ?? Classification.BLOCKED) };
  }
  if (
    cls === Classification.PARSE_FAILED ||
    cls === Classification.PARSE_ISSUE ||
    display === DisplayStatus.PARSE_ISSUE
  ) {
    return { key: 'parse_failed', label: labelFor(cls ?? Classification.PARSE_FAILED) };
  }
  if (
    cls === Classification.RETRY_REQUIRED ||
    cls === Classification.EMPTY_BUT_EXPECTED_SCHEDULES ||
    f.render_status === RenderStatus.INCOMPLETE ||
    f.render_status === RenderStatus.UNSTABLE
  ) {
    return { key: 'retry_required', label: labelFor(cls ?? Classification.RETRY_REQUIRED) };
  }
  if (cls === Classification.CONFIRMED_EMPTY) {
    return { key: 'confirmed_empty', label: labelFor(Classification.CONFIRMED_EMPTY) };
  }
  if (cls === Classification.NO_SCHEDULE_DATA) {
    return { key: 'unknown', label: labelFor(Classification.NO_SCHEDULE_DATA) };
  }
  if (cls === Classification.FIXTURE_ONLY || (f.fixture_count > 0 && f.live_count === 0)) {
    return { key: 'fixture', label: labelFor(Classification.FIXTURE_ONLY) };
  }
  if (cls === Classification.LIVE_OK || display === DisplayStatus.LIVE_OK || f.live_count > 0) {
    if (f.last_verified) {
      const ageHours = (Date.now() - f.last_verified) / (1000 * 60 * 60);
      if (ageHours > 48 * 7) {
        return { key: 'stale', label: `Live (stale — ${Math.round(ageHours / 24)}d ago)` };
      }
    }
    return { key: 'live', label: labelFor(Classification.LIVE_OK) };
  }
  if (f.blocked_reason) {
    return { key: 'blocked', label: `Blocked: ${f.blocked_reason}` };
  }
  return { key: 'unknown', label: labelFor(Classification.NO_SCHEDULE_DATA) };
}

/** Full facility row for dashboard + API — never filtered by session count. */
export function mapFacilityRowToApi(f) {
  const status = deriveFacilityStatus(f);
  const row = {
    facility_id: f.id,
    id: f.id,
    name: f.name,
    type: simplifyType(f.type),
    facility_type: f.type,
    schedule_mode: f.schedule_mode,
    data_model: f.data_model ?? null,
    display_status: f.display_status ?? null,
    has_swim_schedule: Boolean(f.has_swim_schedule),
    region: f.region ?? null,
    session_count: f.session_count ?? 0,
    sessions_count: f.session_count ?? 0,
    live_count: f.live_count ?? 0,
    fixture_count: f.fixture_count ?? 0,
    data_source: f.data_source ?? inferDataSource(f),
    quality_score: f.quality_score ?? 0,
    last_verified: f.last_verified ?? null,
    last_updated: f.last_updated ?? null,
    schedule_updated: f.schedule_updated ?? null,
    blocked_reason: f.blocked_reason ?? null,
    blocked_at: f.blocked_at ?? null,
    scrape_classification: f.scrape_classification ?? null,
    render_status: f.render_status ?? null,
    dom_ready: Boolean(f.dom_ready),
    blocked_detected: Boolean(f.blocked_detected),
    tables_found_count: f.tables_found_count ?? 0,
    parsed_sessions_count: f.parsed_sessions_count ?? 0,
    status: status.key,
    sync_status: status.key,
    sync_status_label: status.label,
  };

  row.debug = buildDebugAction({
    ...row,
    sync_status: status.key,
    classification: row.scrape_classification,
  });
  return row;
}

export const FACILITY_STATUS_BASE_SQL = `
  SELECT
    f.id, f.name, f.type, f.address, f.lat, f.lng,
    f.schedule_mode, f.data_model, f.display_status,
    f.has_swim_schedule, f.region, f.last_verified, f.last_updated,
    (SELECT COUNT(*) FROM schedules s WHERE s.facility_id = f.id) AS session_count,
    (SELECT COUNT(*) FROM schedules s WHERE s.facility_id = f.id AND s.data_source = 'live') AS live_count,
    (SELECT COUNT(*) FROM schedules s WHERE s.facility_id = f.id AND s.data_source = 'fixture') AS fixture_count,
    (SELECT MAX(s.last_updated) FROM schedules s WHERE s.facility_id = f.id) AS schedule_updated,
    b.reason AS blocked_reason,
    b.blocked_at AS blocked_at,
    d.classification AS scrape_classification,
    d.data_source AS data_source,
    d.quality_score AS quality_score,
    d.render_status AS render_status,
    d.dom_ready AS dom_ready,
    d.blocked_detected AS blocked_detected,
    d.tables_found_count AS tables_found_count,
    d.parsed_sessions_count AS parsed_sessions_count,
    d.updated_at AS diagnostic_updated
  FROM facilities f
  LEFT JOIN blocked_facilities b ON b.facility_id = f.id
  LEFT JOIN facility_scrape_diagnostics d ON d.facility_id = f.id
`;

export const FACILITY_STATUS_SQL = `${FACILITY_STATUS_BASE_SQL} ORDER BY f.name`;

export function getFacilityStatusRow(database, facilityId) {
  return database.prepare(`${FACILITY_STATUS_BASE_SQL} WHERE f.id = ?`).get(facilityId);
}
