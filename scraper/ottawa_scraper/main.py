"""Main scraper entry point."""

from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from datetime import datetime
from pathlib import Path

from .config import SNAPSHOTS_DIR
from .discovery.facility_discovery import discover_facilities
from .fetchers.http_fetcher import HttpFetcher
from .fetchers.playwright_fetcher import PlaywrightFetcher
from .parsers.facility_parser import parse_facility
from .parsers.schedule_parser import expand_recurring_entries, parse_schedule_tables

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


def scrape_all(use_playwright_fallback: bool = True) -> dict:
    http = HttpFetcher()
    playwright = PlaywrightFetcher() if use_playwright_fallback else None
    facilities_data = []
    scrape_logs = []

    discovered = discover_facilities(http)
    for facility in discovered:
        start = time.time()
        log_entry = {
            "facility_id": facility.slug,
            "status": "success",
            "message": None,
            "html_snapshot_path": None,
            "content_hash": None,
            "duration_ms": 0,
            "created_at": int(time.time() * 1000),
        }

        try:
            try:
                result = http.fetch(facility.url)
            except Exception:
                if playwright is None:
                    raise
                logger.warning("HTTP failed for %s, trying Playwright", facility.slug)
                result = playwright.fetch(facility.url)

            snapshot_path = SNAPSHOTS_DIR / f"{facility.slug}_{int(time.time())}.html"
            snapshot_path.write_text(result.html, encoding="utf-8")
            log_entry["html_snapshot_path"] = str(snapshot_path)
            log_entry["content_hash"] = result.content_hash

            parsed_facility = parse_facility(
                result.html, facility.slug, facility.name, facility.address
            )
            tables = parse_schedule_tables(result.html)
            all_entries = []
            for table in tables:
                all_entries.extend(table.entries)

            expanded = expand_recurring_entries(all_entries)

            facilities_data.append({
                "id": facility.slug,
                "name": parsed_facility.name,
                "address": parsed_facility.address,
                "postal_code": parsed_facility.postal_code,
                "latitude": parsed_facility.latitude,
                "longitude": parsed_facility.longitude,
                "region": facility.region,
                "url": facility.url,
                "content_hash": result.content_hash,
                "phone": parsed_facility.phone,
                "schedules": [
                    {
                        "category": e.category,
                        "raw_category": e.raw_category,
                        "schedule_type": e.schedule_type,
                        "day_of_week": e.day_of_week,
                        "date": e.date,
                        "start_time": e.start_time,
                        "end_time": e.end_time,
                        "notes": e.notes,
                        "date_range_start": e.date_range_start,
                        "date_range_end": e.date_range_end,
                    }
                    for e in expanded
                ],
            })
            logger.info(
                "Scraped %s: %d schedule entries",
                facility.slug,
                len(expanded),
            )
        except Exception as exc:
            log_entry["status"] = "error"
            log_entry["message"] = str(exc)
            logger.exception("Failed to scrape %s", facility.slug)
        finally:
            log_entry["duration_ms"] = int((time.time() - start) * 1000)
            scrape_logs.append(log_entry)

    return {
        "scraped_at": datetime.utcnow().isoformat() + "Z",
        "facilities": facilities_data,
        "scrape_logs": scrape_logs,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Ottawa Swim Finder scraper")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("output.json"),
        help="Output JSON path",
    )
    parser.add_argument(
        "--no-playwright",
        action="store_true",
        help="Disable Playwright fallback",
    )
    args = parser.parse_args()

    data = scrape_all(use_playwright_fallback=not args.no_playwright)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(data, indent=2), encoding="utf-8")
    logger.info("Wrote %d facilities to %s", len(data["facilities"]), args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())
