const CHALLENGE_SIGNATURES = [
  'pardon our interruption',
  'access denied',
  'cloudflare',
  'captcha',
  'cf-browser-verification',
  'just a moment',
  'enable javascript and cookies',
];

const SWIM_KEYWORDS = [
  'lane swim',
  'leisure swim',
  'public swim',
  'family swim',
  'aquafit',
  'aqua fit',
  'swim schedule',
  'therapeutic',
];

const DAY_HEADERS = /monday|tuesday|wednesday|thursday|friday|saturday|sunday|\bmon\b|\btue\b|\bwed\b|\bthu\b|\bfri\b|\bsat\b|\bsun\b/i;
const DATE_HEADER = /\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{1,2}\b/i;

export function isChallengeHtml(html) {
  const lower = (html || '').toLowerCase();
  return CHALLENGE_SIGNATURES.some((s) => lower.includes(s));
}

export function countSwimTablesInHtml(html) {
  const lower = html.toLowerCase();
  const tableBlocks = html.match(/<table[\s\S]*?<\/table>/gi) ?? [];
  let count = 0;
  for (const block of tableBlocks) {
    const cap = block.match(/<caption[^>]*>([\s\S]*?)<\/caption>/i)?.[1] ?? '';
    const ctx = (cap + block.slice(0, 400)).toLowerCase();
    if (ctx.includes('swim') || ctx.includes('aquafit')) count++;
  }
  return count;
}

export function hasScheduleSignals(html) {
  const lower = (html || '').toLowerCase();
  if (countSwimTablesInHtml(html) > 0) return true;
  if (DAY_HEADERS.test(html) && SWIM_KEYWORDS.some((k) => lower.includes(k))) return true;
  if (DATE_HEADER.test(html) && lower.includes('swim')) return true;
  return false;
}

/**
 * Render validation gate — must pass before parsing.
 */
export function validateRenderedPage(html) {
  if (!html || html.length < 500) {
    return { valid: false, blocked: false, reason: 'html_too_small', domReady: false };
  }
  if (isChallengeHtml(html)) {
    return { valid: false, blocked: true, reason: 'challenge_page', domReady: false };
  }
  const tables = countSwimTablesInHtml(html);
  const signals = hasScheduleSignals(html);
  if (!signals && tables === 0) {
    return { valid: false, blocked: false, reason: 'no_schedule_signals', domReady: false };
  }
  return { valid: true, blocked: false, reason: 'ok', domReady: true, tablesFound: tables };
}

export function shouldRejectWrite({ parsedCount, baselineCount, html, swimMentions = 0 }) {
  if (isChallengeHtml(html)) {
    return { reject: true, reason: 'challenge_page' };
  }
  if (parsedCount === 0 && baselineCount > 0 && hasScheduleSignals(html)) {
    return { reject: true, reason: 'parse_failed_with_baseline' };
  }
  if (parsedCount === 0 && swimMentions >= 3) {
    return { reject: true, reason: 'parse_empty_but_html_has_swims' };
  }
  if (baselineCount >= 10 && parsedCount < baselineCount * 0.6) {
    return { reject: true, reason: `session_drop_${baselineCount}_to_${parsedCount}` };
  }
  return { reject: false };
}

export function countSwimMentions(html) {
  const lower = html.toLowerCase();
  let count = 0;
  for (const kw of SWIM_KEYWORDS) {
    const matches = lower.match(new RegExp(kw.replace(/\s/g, '\\s+'), 'g'));
    count += matches ? matches.length : 0;
  }
  return count;
}
