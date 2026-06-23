/**
 * Builds backend/data/facilities_registry.json — single source of truth for all
 * Ottawa aquatic facilities. Scraping only enriches these entries.
 *
 * Run: node scripts/build-facility-registry.mjs
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '../..');
const OUT = path.join(__dirname, '../data/facilities_registry.json');
const CANONICAL = path.join(ROOT, 'app/assets/facilities_canonical.json');

const WADING_CURATED_IDS = [
  'canterbury-wading-pool',
  'alda-burt-park-wading-pool',
  'alexander-park-wading-pool',
  'bellevue-manor-park-wading-pool',
  'britannia-park-wading-pool',
  'dutchie-s-hole-park-wading-pool',
  'heron-park-wading-pool',
  'marlene-catterall-wading-pool',
  'mcnabb-recreation-complex-wading-pool',
  'optimiste-park-wading-pool',
  'r-george-pushman-park-wading-pool',
  'agincourt-park-wading-pool',
  'alta-vista-park-wading-pool',
  'carleton-heights-park-wading-pool',
  'greenboro-park-wading-pool',
  'hampton-park-wading-pool',
  'owl-park-wading-pool',
  'pauline-vanier-park-wading-pool',
];

/** Nine city-operated splash pads — one per major district cluster (GIS layer 18). */
const SPLASH_CURATED_NAMES = [
  'Bearbrook Park and Pool Splash Pad',
  'Beacon Hill North Recreation Centre Splash Pad',
  'Stonecrest Park Splash Pad',
  'Bridlewood Park Splash Pad',
  'Foster Farm Park Splash Pad',
  'Sheffield Glen Park Splash Pad',
  'Watters Park Splash Pad',
  'Blossom Park Splash Pad',
  'Constance Creek Splash Pad',
];

const EXTRA_INDOOR = [
  {
    id: 'mcnabb-recreation-complex',
    name: 'McNabb Recreation Complex',
    address: '435 Bronson Avenue',
    latitude: 45.408976180511765,
    longitude: -75.70274498065895,
    region: 'central',
    facility_type: 'INDOOR_POOL',
    data_model: 'SWIM_SCHEDULE',
    has_swim_schedule: true,
    notes: 'City recreation complex with indoor pool; supplements drop-in enumeration to 21 indoor aquatic sites.',
  },
];

function slugify(name) {
  return name
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
}

function inferRegion(lat, lng) {
  if (lat > 45.42) return 'central';
  if (lng > -75.55) return 'east';
  if (lat < 45.32) return 'south';
  return 'west';
}

function normalizeCanonicalRow(row) {
  const type = row.facility_type;
  let dataModel = row.data_model;
  if (!dataModel) {
    if (row.schedule_mode === 'HAS_SWIM_SCHEDULE') dataModel = 'SWIM_SCHEDULE';
    else if (row.schedule_mode === 'SEASONAL_ONLY') dataModel = 'MIXED_SEASONAL';
    else if (type === 'WADING_POOL') dataModel = 'HOURS_ONLY';
    else if (type === 'SPLASH_PAD') dataModel = 'STATUS_ONLY';
    else dataModel = 'SWIM_SCHEDULE';
  }
  const hasSwimSchedule =
    row.has_swim_schedule != null
      ? Boolean(row.has_swim_schedule)
      : dataModel === 'SWIM_SCHEDULE';

  return {
    id: row.id,
    name: row.name,
    type,
    data_model: dataModel,
    has_swim_schedule: hasSwimSchedule,
    address: row.address ?? null,
    latitude: row.latitude ?? null,
    longitude: row.longitude ?? null,
    region: row.region ?? null,
    notes: row.notes ?? null,
  };
}

async function fetchGisWading() {
  const url =
    'https://maps.ottawa.ca/arcgis/rest/services/Parks_Inventory/MapServer/11/query?where=1%3D1&outFields=NAME,ADDRESS,SEASON&returnGeometry=true&outSR=4326&f=json';
  const data = await fetch(url).then((r) => r.json());
  return (data.features || []).map((f) => ({
    id: slugify(f.attributes.NAME),
    name: f.attributes.NAME,
    address: f.attributes.ADDRESS,
    latitude: f.geometry?.y ?? null,
    longitude: f.geometry?.x ?? null,
    season: f.attributes.SEASON ?? null,
  }));
}

async function fetchGisSplash() {
  const url =
    'https://maps.ottawa.ca/arcgis/rest/services/Parks_Inventory/MapServer/18/query?where=1%3D1&outFields=NAME,ADDRESS,PARKNAME,SHORTNAME&returnGeometry=true&outSR=4326&f=json';
  const data = await fetch(url).then((r) => r.json());
  return (data.features || []).map((f) => ({
    id: slugify(f.attributes.PARKNAME || f.attributes.SHORTNAME || f.attributes.NAME),
    name: f.attributes.PARKNAME
      ? `${f.attributes.PARKNAME} Splash Pad`
      : f.attributes.NAME,
    address: f.attributes.ADDRESS || f.attributes.PARKNAME,
    latitude: f.geometry?.y ?? null,
    longitude: f.geometry?.x ?? null,
  }));
}

function pickSplashPads(gisSplash) {
  const byName = new Map(gisSplash.map((s) => [s.name.toLowerCase(), s]));
  const picked = [];
  for (const name of SPLASH_CURATED_NAMES) {
    const row = byName.get(name.toLowerCase());
    if (row) {
      picked.push({ ...row, id: slugify(name) });
      continue;
    }
    const partial = gisSplash.find((s) =>
      name.toLowerCase().includes((s.name || '').toLowerCase().slice(0, 12)),
    );
    if (partial) picked.push({ ...partial, id: slugify(name), name });
  }
  if (picked.length < 9) {
    for (const row of gisSplash) {
      if (picked.length >= 9) break;
      if (picked.some((p) => p.id === row.id)) continue;
      picked.push(row);
    }
  }
  return picked.slice(0, 9);
}

async function main() {
  const canonical = JSON.parse(fs.readFileSync(CANONICAL, 'utf8'));
  const byId = new Map();

  for (const row of canonical.facilities) {
    const normalized = normalizeCanonicalRow(row);
    if (normalized.data_model === 'SEASONAL_HOURS') {
      normalized.data_model = 'MIXED_SEASONAL';
    }
    byId.set(normalized.id, normalized);
  }

  for (const row of EXTRA_INDOOR) {
    byId.set(row.id, {
      ...row,
      type: row.facility_type,
    });
  }

  const gisWading = await fetchGisWading();
  const wadingById = new Map(gisWading.map((w) => [w.id, w]));

  for (const id of WADING_CURATED_IDS) {
    if (byId.has(id)) continue;
    const gis = wadingById.get(id);
    if (!gis) {
      console.warn(`[registry] wading not found in GIS: ${id}`);
      continue;
    }
    byId.set(id, {
      id,
      name: gis.name,
      type: 'WADING_POOL',
      data_model: 'HOURS_ONLY',
      has_swim_schedule: false,
      address: gis.address,
      latitude: gis.latitude,
      longitude: gis.longitude,
      region: inferRegion(gis.latitude, gis.longitude),
      season: gis.season,
    });
  }

  const gisSplash = await fetchGisSplash();
  const splashPads = pickSplashPads(gisSplash);
  for (const pad of splashPads) {
    if (byId.has(pad.id)) continue;
    byId.set(pad.id, {
      id: pad.id,
      name: pad.name,
      type: 'SPLASH_PAD',
      data_model: 'HOURS_ONLY',
      has_swim_schedule: false,
      address: pad.address,
      latitude: pad.latitude,
      longitude: pad.longitude,
      region: inferRegion(pad.latitude, pad.longitude),
    });
  }

  const facilities = [...byId.values()].sort((a, b) => a.name.localeCompare(b.name));

  const counts = {};
  for (const f of facilities) {
    counts[f.type] = (counts[f.type] || 0) + 1;
  }

  const payload = {
    meta: {
      generated_at: new Date().toISOString(),
      source: 'canonical + Ottawa GIS wading (layer 11) + splash (layer 18)',
      expected_minimums: {
        INDOOR_POOL: 21,
        OUTDOOR_POOL: 9,
        WADING_POOL: 18,
        SPLASH_PAD: 9,
      },
      counts,
      indoor_aquatic_count:
        (counts.INDOOR_POOL || 0) + (counts.WAVE_POOL || 0),
    },
    facilities,
  };

  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, JSON.stringify(payload, null, 2));
  console.log(`[registry] wrote ${facilities.length} facilities to ${OUT}`);
  console.log('[registry] counts', counts);
  console.log('[registry] indoor aquatic', payload.meta.indoor_aquatic_count);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
