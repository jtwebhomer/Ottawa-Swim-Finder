# Ottawa Swim Finder — Self-Hosted Backend (Windows)

Production API server for your home PC. Expose via **router port forwarding** on port **3000**.

```
http://YOUR_PUBLIC_IP:3000
```

## Quick start (Windows)

```powershell
cd backend
npm install
npx playwright install chromium
copy .env.example .env
# Edit .env — set API_KEY to a long random secret
npm start
```

Server binds to `0.0.0.0:3000` (all interfaces).

## Security

Every request **must** include:

```
x-api-key: YOUR_SECRET_FROM_.env
```

Missing or invalid key → `401 Unauthorized`.

## Router setup

1. Assign your PC a static LAN IP (e.g. `192.168.1.50`)
2. Port forward **TCP 3000** → your PC's LAN IP
3. Find public IP: https://whatismyip.com
4. Test: `curl -H "x-api-key: YOUR_KEY" http://YOUR_PUBLIC_IP:3000/health`

**Windows Firewall:** allow inbound TCP 3000:

```powershell
New-NetFirewallRule -DisplayName "Ottawa Swim API" -Direction Inbound -Protocol TCP -LocalPort 3000 -Action Allow
```

## API endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Liveness (requires API key) |
| GET | `/facilities` | All aquatic facilities |
| GET | `/schedules?facility_id=ID` | Sessions for one facility |
| GET | `/swims/today` | Today's swims grouped by facility |
| GET | `/sync/status` | Sync health and stats |
| POST | `/sync/run` | Trigger full Playwright scrape |

## Scraper

- Playwright Chromium (headless by default)
- Expands dropdowns / accordions
- Scrolls page + waits for network idle
- Sequential scraping with 2–5s random delay
- Retries with exponential backoff (max 3); final retry uses headed browser
- Never overwrites good data on bot blocks or >40% session drops

## Scheduler

- Automatic full sync every **6 hours** (`SYNC_CRON=0 */6 * * *`)
- Manual: `POST /sync/run`
- First run: auto-sync if database has no schedules

## Flutter app

```powershell
flutter run --dart-define=API_BASE_URL=http://YOUR_PUBLIC_IP:3000 --dart-define=API_KEY=your_secret
```

Emulator → host PC: `http://10.0.2.2:3000`

## Run as Windows service (optional)

Use [NSSM](https://nssm.cc/) or Task Scheduler:

```
Program: node
Arguments: src/index.js
Start in: C:\path\to\ottawa_swim_finder\backend
```

## Environment

| Variable | Default | Description |
|----------|---------|-------------|
| `API_KEY` | *(required)* | Shared secret for mobile app |
| `HOST` | `0.0.0.0` | Bind address |
| `PORT` | `3000` | HTTP port |
| `DATABASE_PATH` | `./data/ottawa_swim.db` | SQLite file |
| `SYNC_CRON` | `0 */6 * * *` | Scrape schedule |
| `PLAYWRIGHT_HEADLESS` | `true` | Set `false` for debug |
