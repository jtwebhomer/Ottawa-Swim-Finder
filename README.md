# Ottawa Swim Finder

Find City of Ottawa public pool swim times in one place — instant on launch, searchable, map-based, and fully usable offline.

[![Latest release](https://img.shields.io/github/v/release/jtwebhomer/Ottawa-Swim-Finder)](https://github.com/jtwebhomer/Ottawa-Swim-Finder/releases/latest)

## Download (Android)

Get the latest APK from **[Releases](https://github.com/jtwebhomer/Ottawa-Swim-Finder/releases/latest)** or download [`releases/Ottawa-Swim-Finder-v1.5.0.apk`](releases/Ottawa-Swim-Finder-v1.5.0.apk) directly from this repo.

1. Download `Ottawa-Swim-Finder-v1.5.0.apk`
2. Install on your Android phone or tablet (enable “Install unknown apps” if prompted)
3. Open the app — bundled schedules load immediately; live refresh runs in the background when online

No Google Play listing yet — installs are via the GitHub release APK.

## Features

- **57 Ottawa aquatic facilities** — indoor, outdoor, wave, wading, and splash pads
- **Instant home screen** — bundled seed data on first launch, no blocking sync screen
- **Smart sections** — Swimming Now, Starting Soon, Tonight, and Tomorrow
- **5-tab navigation** — Home, Find Swim, Map, Saved, Settings
- **Offline-first** — schedules stored locally; app stays usable without internet
- **Rate-limit safe sync** — phased background refresh with cache preservation and bot-block handling
- **Map view** — clustered pins with facility bottom sheet and directions
- **Find Swim** — search by date, time, category, facility, and distance
- **Saved swims** — bookmarks with optional reminders
- **Habit hints** — gentle “you usually swim around this time” suggestions (on-device only)
- **Navigate** to any pool in your preferred maps app

## What's new in v1.5.0

- Central backend API sync (`quantumvibe.ca:3000`) with 57-facility registry
- Correct data models for wading pools, splash pads, and seasonal outdoor pools
- HTTP scraper + Chrome extension cache import for blocked Ottawa.ca pages
- Sync dashboard with facility status and direct links to facility pages
- Map and facility screens show hours/seasonal status instead of empty swim states

## What's new in v1.4.0-rc1

Release candidate with production QA and chaos testing:

- Sync mutex and refresh coalescing (no duplicate sync jobs)
- Transactional schedule commits (no partial DB wipes)
- Bot-block / partial sync safety — cached data never overwritten by challenge pages
- Responsive layout fixes for phones and tablets
- Consumer-friendly error and empty states
- 83 automated tests passing

## Project structure

```
ottawa_swim_finder/
├── app/              # Flutter Android app
├── backend/          # Node.js schedule API + sync dashboard
├── chrome-extension/ # Ottawa.ca schedule cache downloader
├── releases/         # Release APKs
├── scraper/      # Python schedule scraper (development / validation)
├── docs/         # Architecture and schema notes
└── scripts/      # Build helpers
```

## Build from source

### Prerequisites

- Flutter SDK 3.44+
- Android Studio with SDK 34+
- Python 3.11+ (optional, for the scraper)

### Flutter app

```bash
cd app
flutter pub get
flutter run
```

Release APK:

```bash
cd app
flutter build apk --release \
  --dart-define=API_BASE_URL=http://quantumvibe.ca:3000 \
  --dart-define=API_KEY=your-api-key
```

Output: `app/build/app/outputs/flutter-apk/app-release.apk`

The map uses **OpenStreetMap** via `flutter_map` with optional offline tile caching. No API key required.

### Python scraper

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

## Data source

Schedules are scraped from [City of Ottawa recreation facility pages](https://ottawa.ca/en/drop-swimming-and-aquafitness/indoor-pools-drop-locations).

This is an **unofficial community tool** — always verify schedules on the official City of Ottawa website.

## License

Source code is provided as-is for personal and community use. Ottawa pool schedule data belongs to the City of Ottawa.
