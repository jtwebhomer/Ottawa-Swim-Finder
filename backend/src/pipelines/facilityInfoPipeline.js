import * as cheerio from 'cheerio';

const STABLE_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/**
 * Pipeline B — lightweight HTTP fetch for facility info (all facilities).
 * No Playwright.
 */
export async function fetchFacilityInfoPage(url) {
  const res = await fetch(url, {
    headers: {
      'User-Agent': STABLE_UA,
      Accept: 'text/html,application/xhtml+xml',
      'Accept-Language': 'en-CA,en;q=0.9',
    },
    redirect: 'follow',
  });

  const html = await res.text();
  return {
    httpStatus: res.status,
    html,
    blocked: res.status === 403 || isBotPage(html),
  };
}

function isBotPage(html) {
  const lower = (html || '').toLowerCase();
  return (
    lower.includes('pardon our interruption') ||
    lower.includes('access denied') ||
    lower.includes('cf-browser-verification')
  );
}

export function parseFacilityInfo(html) {
  const $ = cheerio.load(html || '');
  const text = $('body').text().replace(/\s+/g, ' ').trim();

  const hoursMatch = text.match(
    /(?:hours|open)[^.]{0,120}(?:monday|mon|daily|weekday)[^.]{0,200}/i,
  );
  const seasonMatch = text.match(
    /(?:season|operating)[^.]{0,80}([A-Za-z]+\s+\d{1,2})[^.]{0,40}(?:to|–|-)[^.]{0,40}([A-Za-z]+\s+\d{1,2})/i,
  );

  const address =
    $('address').first().text().trim() ||
    $('[itemprop="streetAddress"]').text().trim() ||
    null;

  return {
    hoursText: hoursMatch ? hoursMatch[0].trim() : null,
    seasonStart: seasonMatch?.[1] ?? null,
    seasonEnd: seasonMatch?.[2] ?? null,
    address,
    pageTitle: $('title').text().trim() || null,
  };
}

export async function runFacilityInfoPipeline(url) {
  const page = await fetchFacilityInfoPage(url);
  if (page.blocked) {
    return { ok: false, blocked: true, info: null, httpStatus: page.httpStatus };
  }
  const info = parseFacilityInfo(page.html);
  return { ok: true, blocked: false, info, httpStatus: page.httpStatus };
}
