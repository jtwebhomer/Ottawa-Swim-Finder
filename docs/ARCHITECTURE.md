# Ottawa Swim Finder — Architecture

## Layered Architecture

```
presentation/   → Screens, widgets, Riverpod/Provider state
domain/         → Entities, repository interfaces, use cases
data/           → SQLite, scrapers, services, repository impls
core/           → Theme, logging, constants, utilities
di/             → get_it service locator registration
```

## Repository Pattern

| Interface | Implementation | Responsibility |
|-----------|----------------|----------------|
| `FacilityRepository` | `FacilityRepositoryImpl` | CRUD facilities, favorites |
| `ScheduleRepository` | `ScheduleRepositoryImpl` | Query/search schedules |
| `ScrapeLogRepository` | `ScrapeLogRepositoryImpl` | Debug logs, snapshots |
| `SettingsRepository` | `SettingsRepositoryImpl` | User preferences |

## Dependency Injection

`get_it` registers singletons at startup in `lib/di/injection.dart`:

- `AppDatabase`
- Repositories
- `SyncService`, `LocationService`, `NotificationService`
- Use cases

`provider` exposes reactive state to widgets.

## Scraper Architecture (Modular)

### Python (`scraper/ottawa_scraper/`)

```
fetchers/
  http_fetcher.py      # requests with retries
  playwright_fetcher.py # JS fallback
discovery/
  facility_discovery.py # list all pool facilities
parsers/
  facility_parser.py    # name, address, coords
  schedule_parser.py    # HTML table → schedule entries
  category_normalizer.py
```

Each parser is independently testable. Site structure changes are isolated to parser modules.

### Dart (`app/lib/data/scraper/`)

Mirrors Python parsers for on-device sync. Uses `http` + `html` packages. Playwright fallback is not available on-device; if JS rendering is required, logs failure and stores snapshot for manual review.

## Sync & Change Detection

1. Compare stored `content_hash` per facility URL
2. Skip download if hash unchanged
3. On change: re-parse, upsert schedules, update `last_updated`
4. Log failures to `scrape_logs` with `html_snapshot_path`

## Background Updates

- **Startup**: `SyncService.syncIfNeeded()` in `main.dart`
- **Periodic**: `workmanager` every 6 hours
- **Manual**: pull-to-refresh on home + settings button

## Map Pin Logic

| Color | Condition |
|-------|-----------|
| Green | Active swim session now at facility |
| Blue | Upcoming swim today, none active |
| Gray | No swims remaining today |

## Occupancy Estimation

When multiple concurrent swim categories overlap at a facility, estimate relative busyness:

```
occupancy_score = sum(concurrent_session_weights)
```

Weights: lane swim = 0.3, public = 0.8, wave = 1.0, aquafit = 0.5 (configurable).

Displayed as Low / Moderate / Busy on facility screen.

## Performance

- Indexes on `schedules(facility_id, date, start_time, category)`
- FTS5 virtual table for facility name search
- Schedule expansion runs at sync time, not query time
- Pagination for timeline view (100 entries per page)

## Testing Strategy

| Layer | Tests |
|-------|-------|
| Parsers | Golden HTML fixtures → expected JSON |
| Repositories | In-memory SQLite |
| Use cases | Mock repositories |
| Integration | Full sync → search flow |
