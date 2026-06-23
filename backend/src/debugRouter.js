import express from 'express';
import { openFacilityDebugPage, getSessionMeta, getActivePage } from './browserSession.js';
import { facilityUrl } from './facilityUrls.js';
import { facilityDebugUrl, isInteractiveSyncMode } from './syncConfig.js';
import { getFacilityStatusRow, mapFacilityRowToApi } from './facilityStatusApi.js';

function localhostOnly(req, res, next) {
  const ip = req.socket?.remoteAddress ?? '';
  const ok =
    ip === '127.0.0.1' ||
    ip === '::1' ||
    ip === '::ffff:127.0.0.1' ||
    ip.endsWith('127.0.0.1');
  if (!ok) {
    return res.status(403).send('Debug routes are localhost-only.');
  }
  next();
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

async function captureDomSnippet(page, maxLen = 4000) {
  if (!page) return null;
  try {
    const html = await page.content();
    return html.slice(0, maxLen);
  } catch {
    return null;
  }
}

export function createDebugRouter(database) {
  const router = express.Router();
  router.use(localhostOnly);

  router.get('/session', (_req, res) => {
    res.json({
      ...getSessionMeta(),
      interactive: isInteractiveSyncMode(),
      debugBase: facilityDebugUrl('example').replace('/example', ''),
    });
  });

  router.get('/facility/:id', async (req, res) => {
    const { id } = req.params;
    const wantsJson =
      req.query.format === 'json' ||
      (req.headers.accept || '').includes('application/json');

    const row = getFacilityStatusRow(database, id);
    if (!row) {
      return wantsJson
        ? res.status(404).json({ error: 'facility not found', facility_id: id })
        : res.status(404).send(`Facility not found: ${id}`);
    }

    const facility = mapFacilityRowToApi(row);

    try {
      const info = await openFacilityDebugPage(id);
      const ottawaUrl = facilityUrl(id);
      const page = getActivePage();
      const screenshotBuf = page
        ? await page.screenshot({ type: 'png', fullPage: false }).catch(() => null)
        : null;
      const domSnippet = await captureDomSnippet(page);

      if (wantsJson) {
        return res.json({
          facility_id: id,
          name: facility.name,
          status: facility.status,
          display_status: facility.display_status,
          sessions_count: facility.sessions_count,
          data_model: facility.data_model,
          debug: facility.debug,
          ottawa_url: ottawaUrl,
          http_status: info.httpStatus,
          render_status: info.renderStatus,
          blocked: info.blocked,
          dom_size: info.domSize,
          tables_found: info.tablesFound,
          page_title: info.title,
          session: getSessionMeta(),
          interactive: isInteractiveSyncMode(),
          screenshot_base64: screenshotBuf ? screenshotBuf.toString('base64') : null,
          dom_snippet: domSnippet,
        });
      }

      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      res.send(`<!DOCTYPE html>
<html><head><title>Debug: ${escapeHtml(facility.name)}</title>
<style>
  body { font-family: system-ui, sans-serif; margin: 24px; max-width: 960px; }
  .meta { background: #f4f4f4; padding: 12px; border-radius: 8px; margin: 16px 0; }
  img { max-width: 100%; border: 1px solid #ccc; border-radius: 4px; }
  a { color: #1565c0; }
  code { background: #eee; padding: 2px 6px; border-radius: 4px; }
  pre { background: #1e1e1e; color: #ddd; padding: 12px; overflow: auto; max-height: 240px; font-size: 11px; }
</style></head><body>
  <h1>Playwright debug — ${escapeHtml(facility.name)}</h1>
  <p>Shared session navigated to facility page. Browser window stays open for manual inspection.</p>
  <div class="meta">
    <div><strong>Facility ID:</strong> <code>${escapeHtml(id)}</code></div>
    <div><strong>Status:</strong> ${escapeHtml(facility.status)} · ${escapeHtml(facility.display_status || '')}</div>
    <div><strong>Ottawa URL:</strong> <a href="${escapeHtml(ottawaUrl)}" target="_blank">${escapeHtml(ottawaUrl)}</a></div>
    <div><strong>HTTP status:</strong> ${info.httpStatus}</div>
    <div><strong>Render:</strong> ${escapeHtml(info.renderStatus)} ${info.blocked ? '(BLOCKED)' : ''}</div>
    <div><strong>DOM size:</strong> ${info.domSize} bytes · tables: ${info.tablesFound}</div>
    <div><strong>Page title:</strong> ${escapeHtml(info.title)}</div>
    <div><strong>Session reused:</strong> ${getSessionMeta().contextReused ? 'yes' : 'no (fresh context)'}</div>
  </div>
  ${screenshotBuf ? `<h2>Viewport screenshot</h2><img src="data:image/png;base64,${screenshotBuf.toString('base64')}" alt="screenshot"/>` : ''}
  ${domSnippet ? `<h2>DOM snippet</h2><pre>${escapeHtml(domSnippet)}</pre>` : ''}
  <p><a href="/debug/facility/${escapeHtml(id)}?format=json">JSON response</a> · <a href="/debug/session">Session status</a> · <a href="/dashboard">Sync dashboard</a></p>
</body></html>`);
    } catch (e) {
      if (wantsJson) {
        return res.status(500).json({ error: e.message, facility_id: id });
      }
      res.status(500).send(`Debug navigation failed: ${escapeHtml(e.message)}`);
    }
  });

  return router;
}
