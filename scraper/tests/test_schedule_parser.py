"""Tests for schedule parser."""

from datetime import date

from ottawa_scraper.parsers.category_normalizer import normalize_category
from ottawa_scraper.parsers.schedule_parser import _extract_times, expand_recurring_entries, parse_schedule_tables
from ottawa_scraper.parsers.time_parser import parse_time_range


SAMPLE_TABLE_HTML = """
<table>
<caption>Kanata Leisure Centre - swim and aquafit - March 23 to June 26</caption>
<tr><th>Activity</th><th>Monday</th><th>Tuesday</th></tr>
<tr><td>Lane swim</td><td>8 - 9 am, 10 am - 1 pm</td><td>n/a</td></tr>
<tr><td>Public swim</td><td>n/a</td><td>5 - 6 pm</td></tr>
<tr><td>Aquafit</td><td>9 - 10 am</td><td>9 - 10 am</td></tr>
</table>
"""


def test_normalize_category():
    assert normalize_category("Lane swim") == "lane_swim"
    assert normalize_category("Public Swim - wave tank") == "general_swim"
    assert normalize_category("Aquafit General - Deep") == "aquafit"
    assert normalize_category("Leisure swim") == "general_swim"
    assert normalize_category("Alternate needs swim *Reservations required") == "general_swim"


def test_extract_times():
    times = _extract_times("8 - 9 am, 10 am - 1 pm")
    assert len(times) == 2
    assert times[0] == ("08:00", "09:00", None)
    assert times[1] == ("10:00", "13:00", None)


def test_noon_crossing_range():
    assert parse_time_range("11", "1 pm") == ("11:00", "13:00")
    assert parse_time_range("10", "1 pm") == ("10:00", "13:00")
    assert parse_time_range("5", "6 pm") == ("17:00", "18:00")


def test_parse_schedule_tables():
    tables = parse_schedule_tables(SAMPLE_TABLE_HTML)
    assert len(tables) == 1
    assert len(tables[0].entries) >= 3
    categories = {e.category for e in tables[0].entries}
    assert "lane_swim" in categories


def test_expand_rolls_forward_expired_season():
    from ottawa_scraper.parsers.schedule_parser import ParsedScheduleEntry

    entry = ParsedScheduleEntry(
        category="lane_swim",
        raw_category="Lane swim",
        schedule_type="recurring",
        day_of_week=1,
        date=None,
        start_time="18:00",
        end_time="19:00",
        date_range_start="2025-01-01",
        date_range_end="2025-03-01",
    )
    expanded = expand_recurring_entries([entry], start=date(2026, 6, 22), end=date(2026, 6, 28))
    assert expanded, "Expired season should roll forward, not drop entries"
