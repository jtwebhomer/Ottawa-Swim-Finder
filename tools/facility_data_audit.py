#!/usr/bin/env python3
"""Compare official Ottawa HTML schedule cells vs expected patterns for audit."""
import json
import re
import urllib.request
from datetime import datetime, timedelta
from html import unescape

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-CA,en;q=0.9",
    "Referer": "https://ottawa.ca/en/recreation-and-parks",
}

FACILITIES = [
    ("jack-purcell-community-centre", "Jack Purcell Recreation Centre"),
    ("bob-macquarrie-recreation-complex-orleans", "Bob MacQuarrie Recreation Complex"),
    ("plant-recreation-centre", "Plant Recreation Centre"),
    ("walter-baker-sports-centre", "Walter Baker Sports Centre"),
    ("richcraft-recreation-complex-kanata", "Richcraft Recreation Complex"),
]

DAY_NAMES = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]


def fetch_html(facility_id: str) -> str:
    url = f"https://ottawa.ca/en/recreation-and-parks/facilities/place-listing/{facility_id}"
    req = urllib.request.Request(url, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=45) as resp:
        return resp.read().decode("utf-8", errors="replace")


def strip_tags(text: str) -> str:
    text = re.sub(r"<br\s*/?>", "\n", text, flags=re.I)
    text = re.sub(r"<[^>]+>", " ", text)
    return unescape(re.sub(r"\s+", " ", text)).strip()


def extract_swim_tables(html: str) -> list[dict]:
    tables = []
    for m in re.finditer(r"<table[^>]*>(.*?)</table>", html, re.I | re.S):
        block = m.group(1)
        cap = re.search(r"<caption[^>]*>(.*?)</caption>", block, re.I | re.S)
        title = strip_tags(cap.group(1)) if cap else ""
        if "swim" not in title.lower() and "aquafit" not in title.lower():
            continue
        headers = [
            strip_tags(h).lower()
            for h in re.findall(r"<th[^>]*>(.*?)</th>", block, re.I | re.S)
        ]
        day_cols = {}
        for i, h in enumerate(headers):
            for di, dn in enumerate(DAY_NAMES):
                if dn in h or dn[:3] in h:
                    day_cols[i] = di + 1
        rows = []
        for row in re.findall(r"<tr[^>]*>(.*?)</tr>", block, re.I | re.S):
            cells = re.findall(r"<t[hd][^>]*>(.*?)</t[hd]>", row, re.I | re.S)
            if len(cells) < 2:
                continue
            category = strip_tags(cells[0])
            if not category or category.lower() in DAY_NAMES:
                continue
            if "swim" not in category.lower() and "aquafit" not in category.lower():
                continue
            for col_idx, cell in enumerate(cells[1:], start=1):
                text = strip_tags(cell)
                if not text or text.lower() in ("n/a", "-", ""):
                    continue
                if not re.search(r"\d", text):
                    continue
                rows.append(
                    {
                        "category": category,
                        "col": col_idx,
                        "day_of_week": day_cols.get(col_idx),
                        "source_cell": text,
                    }
                )
        tables.append({"title": title, "rows": rows, "day_cols": day_cols})
    return tables


def audit_facility(facility_id: str, name: str) -> dict:
    today = datetime.now()
    tomorrow = today + timedelta(days=1)
    weekday = today + timedelta(days=1)
    while weekday.weekday() >= 5:
        weekday += timedelta(days=1)
    days_to_sat = (5 - today.weekday()) % 7
    saturday = today + timedelta(days=days_to_sat or 7)

    targets = {
        "today": today,
        "tomorrow": tomorrow,
        "future_weekday": weekday,
        "weekend": saturday,
    }

    try:
        html = fetch_html(facility_id)
    except Exception as e:
        return {"id": facility_id, "name": name, "error": str(e)}

    tables = extract_swim_tables(html)
    source_by_dow = {i: [] for i in range(1, 8)}
    for table in tables:
        for row in table["rows"]:
            dow = row.get("day_of_week")
            if dow:
                source_by_dow[dow].append(row)

    date_summary = {}
    for label, dt in targets.items():
        dow = dt.weekday() + 1
        cells = source_by_dow.get(dow, [])
        date_summary[label] = {
            "date": dt.strftime("%Y-%m-%d"),
            "dow": dow,
            "source_session_cells": len(cells),
            "samples": [c["category"] + ": " + c["source_cell"] for c in cells[:5]],
        }

    return {
        "id": facility_id,
        "name": name,
        "swim_tables": len(tables),
        "total_source_cells": sum(len(t["rows"]) for t in tables),
        "date_summary": date_summary,
    }


if __name__ == "__main__":
    report = [audit_facility(fid, name) for fid, name in FACILITIES]
    print(json.dumps(report, indent=2))
