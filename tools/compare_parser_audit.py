#!/usr/bin/env python3
"""Compare Ottawa HTML source vs Dart ScheduleParser output for audit facilities."""
import json
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36"
    ),
    "Referer": "https://ottawa.ca/en/recreation-and-parks",
}

FACILITIES = [
    "jack-purcell-community-centre",
    "bob-macquarrie-recreation-complex-orleans",
    "plant-recreation-centre",
    "walter-baker-sports-centre",
    "richcraft-recreation-complex-kanata",
]

APP_DIR = Path(__file__).resolve().parents[1] / "app"


def fetch(facility_id: str) -> str:
    url = f"https://ottawa.ca/en/recreation-and-parks/facilities/place-listing/{facility_id}"
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=45) as resp:
        return resp.read().decode("utf-8", errors="replace")


def main() -> int:
    # Run via flutter test harness in facility_data_audit_test.dart
    print("Use: flutter test test/integration/facility_data_audit_test.dart")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
