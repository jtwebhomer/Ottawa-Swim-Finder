import { facilityUrl } from './facilityUrls.js';
import { saveCacheImport } from './cacheImport.js';
import { resolveFacilityRecord } from './facilityRegistry.js';
import { applySwimWrite } from './pipelines/pipelineOrchestrator.js';
import { classifyScrapeOutcome } from './blockClassifier.js';

export function processCacheImport(database, { facilityId, html, url, capturedAt, source = 'extension' }) {
  if (!facilityId || !html) {
    return { status: 400, body: { error: 'facility_id and html required' } };
  }

  const facility = database.prepare('SELECT id FROM facilities WHERE id = ?').get(facilityId);
  if (!facility) {
    return { status: 404, body: { error: 'facility not found', facility_id: facilityId } };
  }

  const saved = saveCacheImport(facilityId, html, {
    captured_at: capturedAt,
    url: url ?? facilityUrl(facilityId),
    source,
  });

  let syncResult = null;
  if (saved.evaluated?.sessionCount > 0) {
    const registry = resolveFacilityRecord({ id: facilityId });
    const outcome = classifyScrapeOutcome({
      blocked: false,
      parseResult: saved.evaluated.parseResult,
      renderStatus: saved.evaluated.renderStatus,
      html,
      httpStatus: 200,
    });
    syncResult = applySwimWrite(database, registry, {
      page: { html, httpStatus: 200, domReady: true },
      parseResult: saved.evaluated.parseResult,
      outcome,
      sourceType: 'cached',
      blocked: false,
      renderStatus: saved.evaluated.renderStatus,
    });
  }

  return {
    status: 200,
    body: {
      ok: true,
      facility_id: facilityId,
      cache_path: saved.path,
      captured_at: saved.capturedAt,
      html_bytes: Buffer.byteLength(html, 'utf8'),
      session_count: saved.evaluated?.sessionCount ?? 0,
      tables_found: saved.evaluated?.tablesFound ?? 0,
      synced: syncResult?.updated ?? false,
      display_status: syncResult?.displayStatus ?? null,
    },
  };
}

export function handleCacheImportRequest(database, req, res) {
  let facilityId;
  let html;
  let url;
  let capturedAt;

  const contentType = req.headers['content-type'] || '';
  if (contentType.includes('application/json')) {
    ({ facility_id: facilityId, html, url, captured_at: capturedAt } = req.body ?? {});
  } else {
    facilityId = req.query.facility_id;
    url = req.query.url;
    capturedAt = req.query.captured_at ? Number(req.query.captured_at) : undefined;
    html = typeof req.body === 'string' ? req.body : '';
  }

  const result = processCacheImport(database, {
    facilityId,
    html,
    url,
    capturedAt,
    source: 'extension',
  });

  res.status(result.status).json(result.body);
}
