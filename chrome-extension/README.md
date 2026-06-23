# Ottawa Swim Schedule Cache — Chrome Extension

Adds a **Download schedule to sync cache** button on Ottawa.ca facility pages. The HTML is sent to the Swim Finder backend, saved under `backend/data/cache/`, and merged into SQLite when it is newer and more complete than existing data.

## Install (developer mode)

1. Open Chrome → `chrome://extensions`
2. Enable **Developer mode**
3. Click **Load unpacked**
4. Select this folder: `chrome-extension/`

## Configure

1. Open extension **Options**
2. Set **API base URL** (default `http://127.0.0.1:3000`, or `http://quantumvibe.ca:3000`)
3. Set **API key** (from `backend/LOCAL_CREDENTIALS.txt`)

## Use

1. Open a facility page on ottawa.ca, e.g.  
   `https://ottawa.ca/en/recreation-and-parks/facilities/place-listing/brewer-pool-and-arena`
2. Scroll to the swim schedule section
3. Click **Download schedule to sync cache**
4. Run repair sync or wait for the next sync — cache is merged automatically

## Backend endpoint

`POST /cache/import` with JSON body:

```json
{
  "facility_id": "brewer-pool-and-arena",
  "html": "<!DOCTYPE html>...",
  "url": "https://ottawa.ca/...",
  "captured_at": 1710000000000
}
```

**Note:** The extension uploads **schedule tables only** (~50–500 KB), not the full page. If you see `413`, reload the extension in `chrome://extensions` and restart the API.
