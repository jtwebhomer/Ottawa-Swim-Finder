const DEFAULT_API_BASE = 'http://127.0.0.1:3000';

async function getSettings() {
  return new Promise((resolve) => {
    chrome.storage.sync.get({ apiBase: DEFAULT_API_BASE, apiKey: '' }, resolve);
  });
}

async function uploadCache({ facilityId, html, url, capturedAt }) {
  const { apiBase, apiKey } = await getSettings();
  const key = (apiKey || '').trim();
  if (!key) {
    throw new Error(
      'API key not set. Right-click the extension icon → Options, paste the key from backend/LOCAL_CREDENTIALS.txt, then Save.',
    );
  }

  const base = (apiBase || DEFAULT_API_BASE).replace(/\/$/, '');
  const params = new URLSearchParams({
    facility_id: facilityId,
    url: url || '',
    captured_at: String(capturedAt || Date.now()),
  });

  const res = await fetch(`${base}/cache/import?${params}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'x-api-key': key,
    },
    body: html,
  });

  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    const hint =
      res.status === 401
        ? ' — check API key in extension Options matches backend LOCAL_CREDENTIALS.txt'
        : res.status === 413
          ? ' — reload extension (schedule-only upload)'
          : '';
    throw new Error((body.error || `Upload failed (${res.status})`) + hint);
  }
  return body;
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === 'UPLOAD_CACHE') {
    uploadCache(message.payload)
      .then((result) => sendResponse({ ok: true, result }))
      .catch((err) => sendResponse({ ok: false, error: err.message || String(err) }));
    return true;
  }

  if (message?.type === 'TEST_CONNECTION') {
    getSettings()
      .then(async ({ apiBase, apiKey }) => {
        const key = (apiKey || '').trim();
        if (!key) throw new Error('API key is empty');
        const base = (apiBase || DEFAULT_API_BASE).replace(/\/$/, '');
        const res = await fetch(`${base}/health`, { headers: { 'x-api-key': key } });
        const body = await res.json().catch(() => ({}));
        if (!res.ok) throw new Error(body.error || `Health check failed (${res.status})`);
        sendResponse({ ok: true, body });
      })
      .catch((err) => sendResponse({ ok: false, error: err.message || String(err) }));
    return true;
  }
});
