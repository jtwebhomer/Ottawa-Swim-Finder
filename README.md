# Ottawa Swim Finder

Aggregate City of Ottawa public pool swim schedules into a single searchable, offline-capable Flutter app.

## Project Structure

```
ottawa_swim_finder/
├── docs/                    # Architecture, schema, implementation plan
├── scraper/                 # Python scraper (requests + BeautifulSoup + Playwright)
│   ├── ottawa_scraper/
│   │   ├── discovery/       # Facility discovery
│   │   ├── fetchers/          # HTTP + Playwright fetchers
│   │   ├── parsers/           # Schedule & facility parsers
│   │   └── snapshots/         # Raw HTML debug snapshots
│   └── tests/
└── app/                     # Flutter application
    ├── lib/
    │   ├── core/              # Theme, logging, utils
    │   ├── data/              # DB, repos, scraper, services
    │   ├── domain/            # Entities, interfaces, use cases
    │   ├── presentation/      # Screens, providers, widgets
    │   └── di/                # Dependency injection
    ├── test/
    └── assets/
```

## Features

- **20 indoor pools** from City of Ottawa
- **Offline-first** SQLite storage with 6-hour background sync
- **Map view** with green/blue/gray pin status
- **Search** by category, facility, date, time, distance
- **Quick filters**: Swimming Now, Within 1 Hour, Tonight, Tomorrow, Weekend
- **Favorites** prioritized in search results
- **Swimming Right Now** city-wide active sessions
- **Timeline view** for any selected day
- **Occupancy estimation** from concurrent sessions
- **Debug screen** with scrape logs and HTML snapshots

## Setup

### Prerequisites

- Flutter SDK 3.44+ (installed at `E:\flutter`)
- Python 3.11+ (for scraper development)
- Android Studio with SDK 34+

### Flutter SDK

Flutter is extracted from `E:\flutter_windows_3.44.3-stable.zip` to `E:\flutter` and added to your user PATH. Open a **new terminal** and verify:

```bash
flutter --version
```

### Flutter App

```bash
cd app
flutter pub get
flutter run
```

The map uses **OpenStreetMap** via `flutter_map` with offline tile caching (`flutter_map_tile_caching`). No API key required.

- Tiles cache automatically as you browse the map
- Settings → **Cache Ottawa map** pre-downloads zoom 10–13 for the city
- Facility pins cluster when zoomed out
- **Navigate** opens your preferred navigation app (Google Maps, Waze, etc.)

### Python Scraper

```bash
cd scraper
pip install -r requirements.txt
playwright install chromium   # optional JS fallback
python -m ottawa_scraper.main --output output.json
```

### Tests

```bash
cd app && flutter test
cd scraper && pytest
```

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md), [docs/DATABASE_SCHEMA.md](docs/DATABASE_SCHEMA.md), and [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md).

## Data Source

Schedules are scraped from [City of Ottawa recreation facility pages](https://ottawa.ca/en/drop-swimming-and-aquafitness/indoor-pools-drop-locations). This is an unofficial community tool — always verify schedules on the official website.
