function facilityIdFromUrl() {
  const match = location.pathname.match(/place-listing\/([^/?#]+)/i);
  return match ? decodeURIComponent(match[1]) : null;
}

const SWIM_TOGGLE_RE =
  /\b(swim|aquafit|aqua\s*fit|aquatic|pool)\b/i;
const NON_SWIM_TOGGLE_RE =
  /\b(weight|cardio|gymnasium|gym\b|fitness|squash|skat(e|ing)|ice\b|registered|rental|arena|sports hall|pickleball|badminton|basketball|volleyball|tennis|track)\b/i;

function isSwimTable(table) {
  const cap = (table.querySelector('caption')?.innerText || '').toLowerCase();
  const text = (table.innerText || '').toLowerCase().slice(0, 1200);
  const ctx = `${cap} ${text}`;
  return (
    ctx.includes('swim') ||
    ctx.includes('aquafit') ||
    ctx.includes('aqua fit') ||
    ctx.includes('lane') ||
    ctx.includes('leisure') ||
    ctx.includes('therapeutic')
  );
}

function findSwimTables(root = document) {
  return [...root.querySelectorAll('table')].filter(isSwimTable);
}

function scoreSwimToggleLabel(label) {
  const text = (label || '').toLowerCase();
  let score = 0;
  if (SWIM_TOGGLE_RE.test(text)) score += 50;
  if (text.includes('drop-in schedule')) score += 10;
  if (NON_SWIM_TOGGLE_RE.test(text)) score -= 100;
  return score;
}

function findToggleForPanel(panel) {
  if (!panel?.id) return null;
  return document.querySelector(
    `button[aria-controls="${panel.id}"], button[data-target="#${panel.id}"]`,
  );
}

function findSwimSectionByLabel() {
  const toggles = [
    ...document.querySelectorAll('button.collapse-section, button[data-toggle="collapse"]'),
  ];

  let best = null;
  for (const toggle of toggles) {
    const label = toggle.innerText || '';
    const score = scoreSwimToggleLabel(label);
    if (score <= 0) continue;

    const sectionId =
      toggle.getAttribute('aria-controls') ||
      toggle.getAttribute('data-target')?.replace(/^#/, '');
    const panel = sectionId ? document.getElementById(sectionId) : null;
    if (!panel) continue;

    const tableBoost = findSwimTables(panel).length * 20;
    const total = score + tableBoost;
    if (!best || total > best.score) {
      best = { panel, toggle, tables: findSwimTables(panel), score: total, label };
    }
  }
  return best;
}

/** Locate the swim accordion panel — by tables inside panels, not dropdown order. */
function findSwimScheduleHost() {
  const tables = findSwimTables();
  if (tables.length > 0) {
    const byPanel = new Map();

    for (const table of tables) {
      const panel =
        table.closest('.collapse-wrapper, [id^="section-"]') ||
        table.closest('.field--name-field-paragraphs, .layout__region--main, article');
      if (!panel) continue;

      if (!byPanel.has(panel)) {
        byPanel.set(panel, { panel, tables: [], toggle: findToggleForPanel(panel) });
      }
      byPanel.get(panel).tables.push(table);
    }

    let best = null;
    for (const entry of byPanel.values()) {
      const labelScore = scoreSwimToggleLabel(entry.toggle?.innerText || '');
      const score = entry.tables.length * 100 + labelScore;
      if (!best || score > best.score) {
        best = { ...entry, score };
      }
    }
    if (best) return best;
  }

  return findSwimSectionByLabel();
}

function getButtonInsertionPoint(host) {
  if (!host) return null;

  if (host.tables?.length) {
    const lastTable = host.tables[host.tables.length - 1];
    return (
      lastTable.closest('.paragraph--type--table, .table-responsive, .field--name-field-body') ||
      lastTable
    );
  }

  if (host.panel) {
    const panelTables = findSwimTables(host.panel);
    if (panelTables.length) {
      const lastTable = panelTables[panelTables.length - 1];
      return (
        lastTable.closest('.paragraph--type--table, .table-responsive, .field--name-field-body') ||
        lastTable
      );
    }
    return host.panel;
  }

  return null;
}

function captureScheduleHtml() {
  const host = findSwimScheduleHost();
  const root = host?.panel || document;
  const tables = host?.tables?.length ? host.tables : findSwimTables(root);
  const parts = [];

  if (tables.length > 0) {
    if (host?.toggle?.innerText) {
      parts.push(`<h2>${host.toggle.innerText.trim()}</h2>`);
    }
    const section = tables[0].closest('.collapse-wrapper, article, main') || root;
    for (const heading of section.querySelectorAll('h2, h3, h4')) {
      const text = heading.innerText || '';
      if (/schedule|swim|aquatic|season|hours|pool|closure/i.test(text)) {
        parts.push(heading.outerHTML);
      }
    }
    for (const table of tables) {
      parts.push(table.outerHTML);
    }
  } else if (host?.panel) {
    const clone = host.panel.cloneNode(true);
    clone.querySelectorAll('script, style, noscript, svg, iframe, .osf-cache-bar').forEach((el) => el.remove());
    parts.push(clone.innerHTML);
  }

  if (parts.length === 0) {
    throw new Error('No swim schedule tables found — expand the swim drop-in section first.');
  }

  return `<!DOCTYPE html><html><head><meta charset="utf-8"></head><body>${parts.join('\n')}</body></html>`;
}

function uploadViaBackground(facilityId, html) {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendMessage(
      {
        type: 'UPLOAD_CACHE',
        payload: {
          facilityId,
          html,
          url: location.href,
          capturedAt: Date.now(),
        },
      },
      (response) => {
        if (chrome.runtime.lastError) {
          reject(new Error(chrome.runtime.lastError.message));
          return;
        }
        if (!response?.ok) {
          reject(new Error(response?.error || 'Upload failed'));
          return;
        }
        resolve(response.result);
      },
    );
  });
}

function createToolbar(facilityId) {
  const bar = document.createElement('div');
  bar.id = 'osf-cache-bar';
  bar.className = 'osf-cache-bar';

  const host = findSwimScheduleHost();
  const sectionLabel = host?.toggle?.innerText?.trim() || host?.label || 'swim schedule';

  bar.innerHTML = `
    <strong>Ottawa Swim Finder</strong>
    <div class="osf-cache-sub">${sectionLabel}</div>
    <button type="button" class="osf-cache-btn" id="osf-cache-download">Download schedule to sync cache</button>
    <div class="osf-cache-status" id="osf-cache-status"></div>
  `;

  const btn = bar.querySelector('#osf-cache-download');
  const status = bar.querySelector('#osf-cache-status');

  btn.addEventListener('click', async () => {
    btn.disabled = true;
    status.className = 'osf-cache-status';
    status.textContent = 'Uploading schedule HTML to sync cache…';

    try {
      const html = captureScheduleHtml();
      const kb = Math.round(new Blob([html]).size / 1024);
      status.textContent = `Uploading ${kb} KB…`;
      const result = await uploadViaBackground(facilityId, html);
      status.className = 'osf-cache-status ok';
      status.textContent = `Saved ${result.session_count ?? 0} sessions (${result.html_bytes ?? kb * 1024} bytes)${
        result.synced ? ' — synced to database' : ''
      }.`;
    } catch (err) {
      status.className = 'osf-cache-status error';
      status.textContent = err.message || String(err);
    } finally {
      btn.disabled = false;
    }
  });

  return bar;
}

function isBarCorrectlyPlaced(bar, insertionPoint) {
  if (!bar || !insertionPoint) return false;
  return bar.previousElementSibling === insertionPoint;
}

function ensureToolbar() {
  const facilityId = facilityIdFromUrl();
  if (!facilityId) return;

  const host = findSwimScheduleHost();
  const insertionPoint = getButtonInsertionPoint(host);
  if (!insertionPoint) return;

  let bar = document.getElementById('osf-cache-bar');
  if (bar && isBarCorrectlyPlaced(bar, insertionPoint)) return;

  if (bar) bar.remove();
  bar = createToolbar(facilityId);
  insertionPoint.insertAdjacentElement('afterend', bar);
}

function boot() {
  ensureToolbar();
  const observer = new MutationObserver(() => ensureToolbar());
  observer.observe(document.body, { childList: true, subtree: true });
}

if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', boot);
} else {
  boot();
}
