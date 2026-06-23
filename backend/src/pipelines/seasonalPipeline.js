import { DisplayStatus, confidenceScoreForDisplayStatus } from '../facilityRegistry.js';
import { runFacilityInfoPipeline } from './facilityInfoPipeline.js';
import { upsertFacilityMetadata, upsertScrapeDiagnostic } from '../db.js';
import { facilityUrl } from '../scraper.js';

/**
 * Pipeline C — seasonal / hours / status-only facilities.
 * Does NOT attempt swim schedule parsing.
 */
export async function runSeasonalPipeline(database, registry) {
  const url = facilityUrl(registry.id);
  const result = await runFacilityInfoPipeline(url);

  const displayStatus = registry.displayStatusDefault;
  const metadata = {
    hoursText: result.info?.hoursText ?? null,
    seasonStart: result.info?.seasonStart ?? null,
    seasonEnd: result.info?.seasonEnd ?? null,
    address: result.info?.address ?? registry.address,
    pageTitle: result.info?.pageTitle ?? null,
    pipeline: 'seasonal',
    fetchedAt: Date.now(),
  };

  if (result.blocked) {
    upsertScrapeDiagnostic(database, registry.id, {
      classification: DisplayStatus.BLOCKED,
      data_source: 'unknown',
      display_status: DisplayStatus.BLOCKED,
      quality_score: 0,
      confidence_score: 0.1,
      render_status: 'HTTP_BLOCKED',
    });
    return {
      updated: false,
      displayStatus: DisplayStatus.BLOCKED,
      blocked: true,
      metadata,
    };
  }

  upsertFacilityMetadata(database, registry.id, metadata);
  upsertScrapeDiagnostic(database, registry.id, {
    classification: displayStatus,
    data_source: 'live',
    display_status: displayStatus,
    quality_score: 2,
    confidence_score: confidenceScoreForDisplayStatus(displayStatus),
    render_status: 'HTTP_OK',
    parsed_sessions_count: 0,
    url,
  });

  database
    .prepare('UPDATE facilities SET display_status = ?, data_model = ?, has_swim_schedule = ?, last_updated = ? WHERE id = ?')
    .run(displayStatus, registry.dataModel, registry.hasSwimSchedule ? 1 : 0, Date.now(), registry.id);

  return {
    updated: true,
    displayStatus,
    blocked: false,
    metadata,
  };
}
