# Ottawa Swim Finder

Source code for a City of Ottawa public pool schedule app (Flutter + Python scraper).

**Android APK downloads:** [Ottawa-Swim-Finder-Android](https://github.com/jtwebhomer/Ottawa-Swim-Finder-Android/releases/latest)

## Features

- **20 indoor pools** from the City of Ottawa
- **Offline-first** — schedules stored locally after sync
- **Map view** with color-coded pins (active now / upcoming / done for today)
- **Today tab** with swim-type and time filters
- **Find a Swim at…** — pick a time and see what’s on nearby
- **Search** by category, facility, date, time, and distance
- **Favorites** for quick access
- **Navigate** to any pool in your preferred maps app
- **Background sync** every 6 hours (when online)

## Project structure

```
ottawa_swim_finder/
├── app/          # Flutter Android app
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
# After pub get, if ObjectBox build fails on Windows:
#   ../scripts/patch_objectbox.ps1
flutter run
```

Release APK:

```bash
cd app
flutter build apk --release
```

Output: `app/build/app/outputs/flutter-apk/app-release.apk`

The map uses **OpenStreetMap** via `flutter_map` with offline tile caching. No API key required.

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
