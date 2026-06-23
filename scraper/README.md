# Ottawa Swim Finder — Python Scraper

Modular scraper for City of Ottawa pool schedules.

## Usage

```bash
pip install -r requirements.txt
python -m ottawa_scraper.main --output output.json
```

## Architecture

- `discovery/facility_discovery.py` — finds all 20 indoor pools
- `fetchers/http_fetcher.py` — requests with retries
- `fetchers/playwright_fetcher.py` — JS fallback
- `parsers/schedule_parser.py` — HTML table → schedule entries
- `parsers/facility_parser.py` — metadata extraction
- `parsers/category_normalizer.py` — swim type normalization
- `snapshots/` — raw HTML for debugging

## Tests

```bash
pytest tests/
```
