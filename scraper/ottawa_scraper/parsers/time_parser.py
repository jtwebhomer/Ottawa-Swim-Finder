"""Ottawa schedule time parsing utilities."""

from __future__ import annotations

import logging
import re
from datetime import datetime

logger = logging.getLogger(__name__)

TIME_RANGE_PATTERN = re.compile(
    r"((?:\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?)|noon|midnight)\s*(?:[-–]|to)\s*"
    r"((?:\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?)|noon|midnight)",
    re.IGNORECASE,
)
SINGLE_TIME_PATTERN = re.compile(
    r"(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?",
    re.IGNORECASE,
)
NA_VALUES = {"n/a", "na", "-", ""}


def _normalize_period_token(raw: str) -> str:
    return raw.strip().lower().replace(".", "")


def _normalize_time_token(raw: str) -> str:
    lower = raw.strip().lower()
    if lower == "noon":
        return "12 pm"
    if lower == "midnight":
        return "12 am"
    return raw


def _parse_single_minutes(raw: str, reference: str | None = None, end_minutes: int | None = None) -> int | None:
    cleaned = _normalize_period_token(_normalize_time_token(raw))
    has_period = "am" in cleaned or "pm" in cleaned
    match = SINGLE_TIME_PATTERN.search(cleaned)
    if not match:
        return None

    hour12 = int(match.group(1))
    minute = int(match.group(2) or 0)
    period = match.group(3)
    if period:
        period = _normalize_period_token(period)

    if not has_period and reference is not None:
        period = _infer_period_for_start(hour12, reference, end_minutes)

    if period is None and not has_period:
        if hour12 >= 13:
            return hour12 * 60 + minute
        logger.warning("Unparseable time without am/pm: %s", raw)
        return None

    hour24 = hour12 % 12
    if period == "pm":
        hour24 += 12
    if period == "am" and hour12 == 12:
        hour24 = 0
    return hour24 * 60 + minute


def _infer_period_for_start(hour12: int, reference: str, end_minutes: int | None) -> str | None:
    ref = _normalize_period_token(reference)
    ref_match = SINGLE_TIME_PATTERN.search(ref)
    if not ref_match:
        return None

    ref_hour = int(ref_match.group(1))
    ref_minute = int(ref_match.group(2) or 0)
    ref_period = ref_match.group(3)
    if not ref_period:
        return None
    ref_period = _normalize_period_token(ref_period)

    ref_hour24 = ref_hour % 12
    if ref_period == "pm":
        ref_hour24 += 12
    if ref_period == "am" and ref_hour == 12:
        ref_hour24 = 0
    resolved_end = end_minutes if end_minutes is not None else ref_hour24 * 60 + ref_minute

    if ref_period == "pm" and hour12 > ref_hour:
        am_start = 0 if hour12 == 12 else hour12 * 60
        if am_start < resolved_end <= am_start + 8 * 60:
            return "am"

    candidates = ["am", "pm"] if ref_period == "pm" else ["am", "pm"]
    for candidate in candidates:
        hour24 = hour12 % 12
        if candidate == "pm":
            hour24 += 12
        if candidate == "am" and hour12 == 12:
            hour24 = 0
        start = hour24 * 60
        duration = resolved_end - start
        if 15 <= duration <= 8 * 60:
            return candidate

    return ref_period


def _format_minutes(total_minutes: int) -> str:
    hour = total_minutes // 60
    minute = total_minutes % 60
    return f"{hour:02d}:{minute:02d}"


def parse_time_range(start_raw: str, end_raw: str) -> tuple[str, str] | None:
    end_minutes = _parse_single_minutes(end_raw)
    if end_minutes is None:
        logger.warning("Failed to parse end time: %s", end_raw)
        return None

    start_minutes = _parse_single_minutes(start_raw, reference=end_raw, end_minutes=end_minutes)
    if start_minutes is None:
        logger.warning("Failed to parse start time: %s (ref=%s)", start_raw, end_raw)
        return None

    if start_minutes >= end_minutes:
        logger.warning("Invalid time range %s - %s", start_raw, end_raw)
        return None

    return _format_minutes(start_minutes), _format_minutes(end_minutes)


def extract_times(cell_text: str) -> list[tuple[str, str, str | None]]:
    if cell_text.strip().lower() in NA_VALUES:
        return []

    notes: str | None = None
    if "play free" in cell_text.lower():
        notes = "Play Free"

    results: list[tuple[str, str, str | None]] = []
    for match in TIME_RANGE_PATTERN.finditer(cell_text):
        parsed = parse_time_range(match.group(1), match.group(2))
        if parsed:
            results.append((parsed[0], parsed[1], notes))
        else:
            logger.warning("Dropped unparsed cell fragment: %s", match.group(0))

    if not results and _looks_like_schedule_cell(cell_text):
        logger.warning("No parseable ranges in schedule cell: %s", cell_text)

    return results


def _looks_like_schedule_cell(text: str) -> bool:
    lower = text.lower()
    return lower not in NA_VALUES and any(ch.isdigit() for ch in text) and (
        "am" in lower or "pm" in lower or ":" in text
    )
