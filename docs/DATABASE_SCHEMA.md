# Ottawa Swim Finder — Database Schema

SQLite database: `ottawa_swim_finder.db` (version 1)

## Tables

### facilities

| Column | Type | Notes |
|--------|------|-------|
| id | TEXT PK | slug, e.g. `kanata-leisure-centre-and-wave-pool` |
| name | TEXT NOT NULL | Display name |
| address | TEXT | Street address |
| postal_code | TEXT | |
| latitude | REAL | WGS84 |
| longitude | REAL | WGS84 |
| region | TEXT | central/east/south/west |
| url | TEXT | ottawa.ca page URL |
| content_hash | TEXT | SHA-256 of last fetched HTML |
| last_updated | INTEGER | Unix ms timestamp |
| has_pool | INTEGER | 1 = true |
| metadata_json | TEXT | Extra fields (phone, hours) |

**Indexes**: `idx_facilities_region`, FTS5 on `name`

### schedules

| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK AUTOINCREMENT | |
| facility_id | TEXT FK → facilities.id | |
| category | TEXT NOT NULL | Canonical swim category |
| raw_category | TEXT | Original row label from site |
| schedule_type | TEXT | `recurring` or `special` |
| day_of_week | INTEGER | 1=Mon..7=Sun (recurring) |
| date | TEXT | ISO date YYYY-MM-DD (special or expanded) |
| start_time | TEXT | HH:MM 24h |
| end_time | TEXT | HH:MM 24h |
| notes | TEXT | e.g. "Play Free" |
| date_range_start | TEXT | Source table range start |
| date_range_end | TEXT | Source table range end |
| last_updated | INTEGER | Unix ms |

**Indexes**:
- `idx_schedules_facility_date (facility_id, date)`
- `idx_schedules_category_date (category, date)`
- `idx_schedules_time (date, start_time, end_time)`

### favorites

| Column | Type | Notes |
|--------|------|-------|
| facility_id | TEXT PK FK → facilities.id | |
| created_at | INTEGER | Unix ms |

### scrape_logs

| Column | Type | Notes |
|--------|------|-------|
| id | INTEGER PK AUTOINCREMENT | |
| facility_id | TEXT | Nullable for global errors |
| status | TEXT | success / error / skipped |
| message | TEXT | Error or info message |
| html_snapshot_path | TEXT | Relative path to snapshot file |
| content_hash | TEXT | |
| duration_ms | INTEGER | |
| created_at | INTEGER | Unix ms |

### settings

| Column | Type | Notes |
|--------|------|-------|
| key | TEXT PK | |
| value | TEXT | JSON-encoded |

**Default settings**:
- `last_sync_at`: timestamp
- `sync_interval_hours`: 6
- `notify_favorites`: false
- `notify_nearby`: false
- `notify_daily_reminder`: false
- `daily_reminder_time`: "08:00"

## Migrations

Managed by `AppDatabase` with `onUpgrade` callbacks. Version tracked in `PRAGMA user_version`.

## Entity Relationships

```
facilities 1──* schedules
facilities 1──0..1 favorites
facilities 1──* scrape_logs
```
