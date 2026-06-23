"""Parse schedule tables from facility pages."""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta

from bs4 import BeautifulSoup, Tag
from dateutil import parser as date_parser

from .category_normalizer import is_swim_row, normalize_category
from .time_parser import extract_times

logger = logging.getLogger(__name__)

DAY_NAMES = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
NA_VALUES = {"n/a", "na", "-", ""}


@dataclass
class ParsedScheduleEntry:
    category: str
    raw_category: str
    schedule_type: str
    day_of_week: int | None
    date: str | None
    start_time: str
    end_time: str
    notes: str | None = None
    date_range_start: str | None = None
    date_range_end: str | None = None


@dataclass
class ParsedScheduleTable:
    title: str
    date_range_start: str | None
    date_range_end: str | None
    schedule_type: str
    entries: list[ParsedScheduleEntry] = field(default_factory=list)


def _extract_times(cell_text: str) -> list[tuple[str, str, str | None]]:
    return extract_times(cell_text)


def _parse_date_range(title: str) -> tuple[str | None, str | None]:
    """Extract date range from table title like 'March 23 to June 26'."""
    match = re.search(
        r"([A-Za-z]+\s+\d{1,2})\s+to\s+([A-Za-z]+\s+\d{1,2})",
        title,
        re.IGNORECASE,
    )
    if not match:
        return None, None
    try:
        year = datetime.now().year
        start = date_parser.parse(f"{match.group(1)} {year}").date()
        end = date_parser.parse(f"{match.group(2)} {year}").date()
        if end < start:
            end = end.replace(year=year + 1)
        today = date.today()
        # Cross-year season (e.g. Sept–June): in Jan–Jun the start is last year.
        if today < start and end.year == start.year + 1:
            start = start.replace(year=start.year - 1)
            end = end.replace(year=end.year - 1)
        while end < today:
            start = start.replace(year=start.year + 1)
            end = end.replace(year=end.year + 1)
        return start.isoformat(), end.isoformat()
    except (ValueError, TypeError):
        return None, None


def _is_swim_table(title: str) -> bool:
    lower = title.lower()
    return "swim" in lower or "aquafit" in lower


def _column_day_index(header: str) -> int | None:
    lower = header.lower().strip()
    for i, day in enumerate(DAY_NAMES):
        if day in lower or day[:3] in lower:
            return i + 1
    return None


def parse_schedule_tables(html: str) -> list[ParsedScheduleTable]:
    soup = BeautifulSoup(html, "lxml")
    tables: list[ParsedScheduleTable] = []

    for table in soup.find_all("table"):
        caption = table.find("caption")
        title = caption.get_text(" ", strip=True) if caption else ""
        if not title:
            prev = table.find_previous(["h2", "h3", "h4"])
            title = prev.get_text(" ", strip=True) if prev else ""

        if not _is_swim_table(title):
            continue

        range_start, range_end = _parse_date_range(title)
        schedule_type = "recurring" if range_start else "special"

        headers_row = table.find("tr")
        headers = (
            [th.get_text(" ", strip=True) for th in headers_row.find_all("th")]
            if headers_row
            else []
        )
        if len(headers) < 2:
            continue

        day_columns: dict[int, int] = {}
        special_dates: dict[int, str] = {}

        for col_idx, header in enumerate(headers):
            day_idx = _column_day_index(header)
            if day_idx:
                day_columns[col_idx] = day_idx
            else:
                try:
                    parsed = date_parser.parse(header, fuzzy=True)
                    special_dates[col_idx] = parsed.date().isoformat()
                    schedule_type = "special"
                except (ValueError, TypeError):
                    pass

        parsed_table = ParsedScheduleTable(
            title=title,
            date_range_start=range_start,
            date_range_end=range_end,
            schedule_type=schedule_type,
        )

        for row in table.find_all("tr"):
            cells = row.find_all(["td", "th"])
            if len(cells) < 2:
                continue

            raw_category = cells[0].get_text(" ", strip=True)
            if not raw_category or raw_category.lower() in DAY_NAMES:
                continue
            if not is_swim_row(raw_category):
                continue

            category = normalize_category(raw_category)

            for col_idx in range(1, len(cells)):
                cell_text = cells[col_idx].get_text(" ", strip=True)
                times = _extract_times(cell_text)
                if not times:
                    continue

                for start, end, notes in times:
                    entry = ParsedScheduleEntry(
                        category=category,
                        raw_category=raw_category,
                        schedule_type=schedule_type,
                        day_of_week=day_columns.get(col_idx),
                        date=special_dates.get(col_idx),
                        start_time=start,
                        end_time=end,
                        notes=notes,
                        date_range_start=range_start,
                        date_range_end=range_end,
                    )
                    parsed_table.entries.append(entry)

        if parsed_table.entries:
            tables.append(parsed_table)

    return tables


def expand_recurring_entries(
    entries: list[ParsedScheduleEntry],
    start: date | None = None,
    end: date | None = None,
) -> list[ParsedScheduleEntry]:
    """Expand recurring weekly entries into concrete dates."""
    if not entries:
        return []

    expanded: list[ParsedScheduleEntry] = []
    today = date.today()
    range_start = start or today
    range_end = end or (today + timedelta(days=90))

    for entry in entries:
        if entry.schedule_type == "special" and entry.date:
            expanded.append(entry)
            continue

        if not entry.day_of_week:
            continue

        table_start = (
            date.fromisoformat(entry.date_range_start)
            if entry.date_range_start
            else range_start
        )
        table_end = (
            date.fromisoformat(entry.date_range_end)
            if entry.date_range_end
            else range_end
        )

        effective_start = max(range_start, table_start)
        effective_end = min(range_end, table_end)
        if effective_end < effective_start:
            continue

        current = effective_start
        while current <= effective_end:
            if current.isoweekday() == entry.day_of_week:
                expanded.append(
                    ParsedScheduleEntry(
                        category=entry.category,
                        raw_category=entry.raw_category,
                        schedule_type="expanded",
                        day_of_week=entry.day_of_week,
                        date=current.isoformat(),
                        start_time=entry.start_time,
                        end_time=entry.end_time,
                        notes=entry.notes,
                        date_range_start=entry.date_range_start,
                        date_range_end=entry.date_range_end,
                    )
                )
            current += timedelta(days=1)

    return expanded
