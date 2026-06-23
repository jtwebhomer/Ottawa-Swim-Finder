import { DisplayStatus, resolveFacilityRecord, usesSeasonalPipeline, usesSwimSchedulePipeline } from '../facilityRegistry.js';
import {
  getFacilityDataCounts,
  upsertScrapeDiagnostic,
  upsertFacilityMetadata,
  recordBlockedFacility,
} from '../db.js';
import { runFacilityInfoPipeline } from './facilityInfoPipeline.js';
import { runSeasonalPipeline } from './seasonalPipeline.js';
import { runSwimSchedulePass } from './swimSchedulePipeline.js';
import { evaluateScheduleWrite, inferExistingQuality } from '../dataSafety.js';
import { replaceSchedulesForFacility, setFacilityBaseline } from '../db.js';
import { facilityUrl } from '../facilityUrls.js';
import { saveFailureSnapshot } from '../scrapeDebug.js';
import { Classification } from '../classification.js';
import { classifyScrapeOutcome, isRepairClassification } from '../blockClassifier.js';
import { logFacilityResult } from '../syncConfig.js';
import { loadBestCacheForFacility, pickBestScheduleSource } from '../cacheImport.js';

const SWIM_RETRY_BACKOFF_MS = [2000, 5000];
const SWIM_MAX_ATTEMPTS = 3;

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function mapParsedRows(sessions, dataSource = 'live') {
  const now = Date.now();
  return sessions.map((row) => ({
    facility_id: row.facility_id,
    date: row.date ?? null,
    start_time: row.start_time,
    end_time: row.end_time,
    activity_type: row.category,
    raw_category: row.raw_category,
    schedule_type: row.schedule_type ?? 'expanded',
    day_of_week: row.day_of_week ?? null,
    date_range_start: row.date_range_start ?? null,
    date_range_end: row.date_range_end ?? null,
    recurrence_pattern: null,
    source: dataSource,
    source_status: dataSource,
    data_source: dataSource,
    confidence_score: dataSource === 'cached' ? 0.92 : 0.95,
    last_updated: now,
  }));
}

function toCandidate(scrapeResult, sourceType) {
  const parsed = scrapeResult.parseResult?.sessions ?? [];
  return {
    sourceType,
    scrapeResult,
    sessionCount: parsed.length,
    tablesFound: scrapeResult.parseResult?.tablesFound ?? 0,
    capturedAt: scrapeResult.capturedAt ?? Date.now(),
    html: scrapeResult.page?.html ?? '',
  };
}

async function runSwimWithRetries(facilityId, weeklyRetries) {
  const attempts = weeklyRetries ? SWIM_MAX_ATTEMPTS : 1;
  let lastHttp = null;

  for (let i = 0; i < attempts; i++) {
    lastHttp = await runSwimSchedulePass(facilityId);
    const outcome = classifyScrapeOutcome({
      blocked: lastHttp.blocked,
      parseResult: lastHttp.parseResult,
      renderStatus: lastHttp.renderStatus,
      html: lastHttp.page.html,
      httpStatus: lastHttp.page.httpStatus,
    });

    if (outcome.displayStatus === DisplayStatus.LIVE_OK) {
      lastHttp = { ...lastHttp, outcome };
      break;
    }

    if (outcome.blockClass === Classification.BLOCKED_HARD) break;

    if (isRepairClassification(outcome.blockClass) && i < attempts - 1) {
      await sleep(SWIM_RETRY_BACKOFF_MS[i] ?? 5000);
      continue;
    }

    lastHttp = { ...lastHttp, outcome };
    break;
  }

  if (!lastHttp.outcome) {
    lastHttp.outcome = classifyScrapeOutcome({
      blocked: lastHttp.blocked,
      parseResult: lastHttp.parseResult,
      renderStatus: lastHttp.renderStatus,
      html: lastHttp.page.html,
      httpStatus: lastHttp.page.httpStatus,
    });
  }

  const cacheBest = loadBestCacheForFacility(facilityId);
  const httpCandidate = toCandidate(lastHttp, 'live');
  const cacheCandidate = cacheBest
    ? {
        sourceType: 'cached',
        scrapeResult: {
          page: { html: cacheBest.html, httpStatus: 200, domReady: true },
          parseResult: cacheBest.parseResult,
          blocked: false,
          renderStatus: cacheBest.renderStatus,
          url: facilityUrl(facilityId),
        },
        sessionCount: cacheBest.sessionCount,
        tablesFound: cacheBest.tablesFound,
        capturedAt: cacheBest.capturedAt,
        html: cacheBest.html,
        outcome: classifyScrapeOutcome({
          blocked: false,
          parseResult: cacheBest.parseResult,
          renderStatus: cacheBest.renderStatus,
          html: cacheBest.html,
          httpStatus: 200,
        }),
      }
    : null;

  const winner = pickBestScheduleSource([
    httpCandidate.sessionCount > 0 ? httpCandidate : null,
    cacheCandidate,
  ]);

  if (!winner) {
    return lastHttp;
  }

  if (winner.sourceType === 'cached') {
    return {
      ...cacheCandidate.scrapeResult,
      outcome: cacheCandidate.outcome,
      sourceType: 'cached',
      capturedAt: cacheCandidate.capturedAt,
      blocked: false,
    };
  }

  return { ...lastHttp, sourceType: 'live' };
}

function applySwimWrite(database, registry, scrapeResult) {
  const { page, parseResult, outcome, sourceType = 'live' } = scrapeResult;
  const { displayStatus, parsed, blockClass } = outcome;
  const dataSource = sourceType === 'cached' ? 'cached' : 'live';

  const counts = getFacilityDataCounts(database, registry.id);
  const existingQuality = inferExistingQuality({
    liveCount: counts.liveCount,
    fixtureCount: counts.fixtureCount,
    cachedCount: counts.cachedCount,
    classification: counts.classification,
  });

  const write = evaluateScheduleWrite({
    newClassification: displayStatus === DisplayStatus.LIVE_OK ? 'LIVE_OK' : displayStatus,
    newSessionCount: parsed.length,
    existingQuality,
    existingSessionCount: counts.totalCount,
    newDataSource: dataSource,
  });

  let finalStatus = displayStatus;
  let updated = false;
  const confidence = parsed.length > 0 ? (dataSource === 'cached' ? 0.92 : 0.95) : 0.1;
  const diagnosticClass = blockClass ?? displayStatus;

  if (write.apply && displayStatus === DisplayStatus.LIVE_OK && parsed.length > 0) {
    replaceSchedulesForFacility(database, registry.id, mapParsedRows(parsed, dataSource));
    setFacilityBaseline(database, registry.id, parsed.length);
    database
      .prepare(
        'UPDATE facilities SET last_verified = ?, last_updated = ?, display_status = ?, data_model = ?, has_swim_schedule = 1 WHERE id = ?',
      )
      .run(Date.now(), Date.now(), DisplayStatus.LIVE_OK, registry.dataModel, registry.id);
    updated = true;
  } else if (!write.apply && counts.totalCount > 0) {
    finalStatus = DisplayStatus.STALE;
  } else if (
    displayStatus === DisplayStatus.BLOCKED ||
    displayStatus === DisplayStatus.PARSE_ISSUE
  ) {
    if (counts.totalCount > 0) finalStatus = DisplayStatus.STALE;
    recordBlockedFacility(database, registry.id, registry.name, diagnosticClass);
    saveFailureSnapshot(registry.id, page.html, diagnosticClass);
  }

  upsertScrapeDiagnostic(database, registry.id, {
    classification: diagnosticClass,
    data_source: updated ? dataSource : counts.liveCount > 0 ? 'live' : counts.cachedCount > 0 ? 'cached' : 'unknown',
    display_status: finalStatus,
    quality_score: write.newScore,
    confidence_score: confidence,
    render_status: scrapeResult.renderStatus,
    dom_ready: page.domReady ? 1 : 0,
    blocked_detected: scrapeResult.blocked ? 1 : 0,
    tables_found_count: parseResult.tablesFound,
    parsed_sessions_count: parsed.length,
    url: facilityUrl(registry.id),
  });

  database.prepare('UPDATE facilities SET display_status = ? WHERE id = ?').run(finalStatus, registry.id);

  const blockedHard = blockClass === Classification.BLOCKED_HARD;
  const blockedTemp = blockClass === Classification.BLOCKED_TEMPORARY;
  const parseFailed = blockClass === Classification.PARSE_FAILED;

  return {
    updated,
    displayStatus: finalStatus,
    blockClass: diagnosticClass,
    parsedCount: updated ? parsed.length : 0,
    blocked: blockedHard || blockedTemp || displayStatus === DisplayStatus.BLOCKED,
    blockedHard,
    requiresManualUnlock: false,
    failed: parseFailed || displayStatus === DisplayStatus.PARSE_ISSUE,
    stale: finalStatus === DisplayStatus.STALE,
    facilityUrl: facilityUrl(registry.id),
    dataSource: updated ? dataSource : null,
  };
}

export async function processFacility(database, rawFacility, { weeklyRetries } = {}) {
  const registry = resolveFacilityRecord(rawFacility);

  const infoResult = await runFacilityInfoPipeline(facilityUrl(registry.id));
  if (infoResult.ok && infoResult.info) {
    upsertFacilityMetadata(database, registry.id, {
      ...infoResult.info,
      pipeline: 'facility_info',
      fetchedAt: Date.now(),
    });
  }

  if (usesSeasonalPipeline(registry)) {
    const seasonal = await runSeasonalPipeline(database, registry);
    logFacilityResult(registry.id, registry.name, { status: seasonal.displayStatus });
    return {
      updated: seasonal.updated,
      displayStatus: seasonal.displayStatus,
      parsedCount: 0,
      blocked: seasonal.blocked,
      failed: false,
      stale: false,
    };
  }

  if (usesSwimSchedulePipeline(registry)) {
    const scrape = await runSwimWithRetries(registry.id, weeklyRetries);
    const result = applySwimWrite(database, registry, scrape);
    logFacilityResult(registry.id, registry.name, {
      status: result.displayStatus,
      blockClass: result.blockClass,
      facilityUrl: result.facilityUrl,
      dataSource: result.dataSource,
    });
    return result;
  }

  upsertScrapeDiagnostic(database, registry.id, {
    classification: registry.displayStatusDefault,
    display_status: registry.displayStatusDefault,
    data_source: 'unknown',
    quality_score: 2,
    confidence_score: 0.85,
  });

  return {
    updated: false,
    displayStatus: registry.displayStatusDefault,
    parsedCount: 0,
    blocked: false,
    failed: false,
    stale: false,
  };
}

export function isRepairTarget(displayStatus, classification) {
  if (isRepairClassification(classification)) return true;
  return (
    displayStatus === DisplayStatus.PARSE_ISSUE ||
    classification === Classification.PARSE_FAILED ||
    classification === Classification.BLOCKED_TEMPORARY
  );
}

export { applySwimWrite };
