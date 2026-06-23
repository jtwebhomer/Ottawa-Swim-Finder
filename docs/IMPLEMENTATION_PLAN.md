# Ottawa Swim Finder — Implementation Plan

## Overview

Ottawa Swim Finder aggregates public swim schedules from all City of Ottawa recreation centres with pools into a single offline-capable Flutter application. Data is collected by a modular Python scraper (development/CI) and an on-device Dart scraper (production sync).

## Phases

### Phase 1 — Foundation (Week 1)
- [x] Project scaffolding and documentation
- [x] SQLite schema and migrations
- [x] Domain entities and repository interfaces
- [x] Dependency injection with `get_it` + `provider`
- [x] Material Design 3 theme

### Phase 2 — Data Collection (Week 1–2)
- [x] Python scraper: facility discovery from indoor pools listing
- [x] Python scraper: schedule table parser (weekly + special-date tables)
- [x] Python scraper: HTML snapshot storage and scrape logging
- [x] Dart scraper mirroring Python logic for on-device sync
- [x] Change detection via content hash per facility page

### Phase 3 — Core App (Week 2–3)
- [x] Sync service (startup, 6-hour periodic, manual refresh)
- [x] Offline search with SQLite indexes
- [x] Map view with pin status colors
- [x] Facility detail screen with directions
- [x] Search with category/date/time/distance filters
- [x] Quick filters (Now, 1 Hour, Tonight, Tomorrow, Weekend)
- [x] Favorites with search prioritization

### Phase 4 — Enhanced Features (Week 3–4)
- [x] Swimming Right Now screen
- [x] City-wide timeline view
- [x] Occupancy estimation from concurrent swim sessions
- [x] Nearest active/lane/public swim cards
- [x] Optional local notifications
- [x] Debug/admin screen with scrape logs and HTML snapshots

### Phase 5 — Quality (Week 4)
- [x] Unit tests (parsers, repositories, use cases)
- [x] Integration tests (database, sync)
- [x] Structured logging
- [x] Error handling and user-facing sync status

## Data Flow

```
ottawa.ca facility pages
        │
        ▼
┌───────────────────┐     ┌──────────────────┐
│  Python Scraper   │     │  Dart Scraper    │
│  (dev / CI)       │     │  (on-device)     │
└────────┬──────────┘     └────────┬─────────┘
         │                         │
         └──────────┬──────────────┘
                    ▼
           ┌────────────────┐
           │  Sync Service  │
           │  (hash check)  │
           └───────┬────────┘
                   ▼
           ┌────────────────┐
           │  SQLite DB     │
           └───────┬────────┘
                   ▼
           ┌────────────────┐
           │  Repositories  │
           └───────┬────────┘
                   ▼
           ┌────────────────┐
           │  UI Screens    │
           └────────────────┘
```

## Ottawa.ca Scraping Strategy

1. **Discovery**: Parse `indoor-pools-drop-locations` for facility names and addresses; map to `place-listing/{slug}` URLs via known slug registry with search fallback.
2. **Facility metadata**: Extract address from listing; geocode via Nominatim (cached) or pre-seeded coordinates in `facilities_seed.json`.
3. **Schedules**: Locate tables under headings containing "swim and aquafit"; support:
   - Weekly recurring tables (Mon–Sun columns)
   - Date-range special tables (e.g., holiday weekends)
4. **Categories**: Normalize row labels to canonical `SwimCategory` enum.
5. **Times**: Parse ranges like `8 - 9 am, 10 am - 1 pm`; expand to concrete `ScheduleEntry` records for each occurrence in the active date range.

## iOS Readiness

- Flutter codebase is platform-agnostic
- `flutter_map` + OpenStreetMap tiles and `geolocator` support iOS
- Background sync uses `workmanager` (iOS BGTaskScheduler)
- Add `ios/` folder via `flutter create --platforms=ios` when building for iOS

## Prerequisites

```bash
# Flutter SDK 3.24+
flutter doctor

# Python 3.11+ for scraper development
cd scraper && pip install -r requirements.txt
playwright install chromium  # optional fallback
```

## Running

```bash
# Scraper (outputs JSON + snapshots)
cd scraper && python -m ottawa_scraper.main --output ../app/assets/seed_data.json

# Flutter app
cd app && flutter pub get && flutter run
```

## API Keys

No map API key required — the app uses OpenStreetMap tiles via `flutter_map`.
