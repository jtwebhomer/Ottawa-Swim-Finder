"""Discover all Ottawa pool facilities."""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass

from bs4 import BeautifulSoup

from ..config import FACILITY_SLUGS, FACILITY_URL_TEMPLATE, INDOOR_POOLS_URL
from ..fetchers.http_fetcher import HttpFetcher

logger = logging.getLogger(__name__)


@dataclass
class DiscoveredFacility:
    name: str
    address: str
    region: str
    slug: str
    url: str


def _slug_for_name(name: str) -> str | None:
    lower = name.lower()
    for fragment, slug in FACILITY_SLUGS.items():
        if fragment in lower:
            return slug
    return None


def discover_facilities(fetcher: HttpFetcher | None = None) -> list[DiscoveredFacility]:
    fetcher = fetcher or HttpFetcher()
    result = fetcher.fetch(INDOOR_POOLS_URL)
    soup = BeautifulSoup(result.html, "lxml")

    facilities: list[DiscoveredFacility] = []
    current_region = "unknown"

    for element in soup.find_all(["h3", "li"]):
        if element.name == "h3":
            text = element.get_text(strip=True).lower()
            if text in ("central", "east", "south", "west"):
                current_region = text
            continue

        text = element.get_text(" ", strip=True)
        if "," not in text:
            continue

        match = re.match(r"^(.+?),\s*(.+)$", text)
        if not match:
            continue

        name, address = match.group(1).strip(), match.group(2).strip()
        slug = _slug_for_name(name)
        if not slug:
            logger.warning("No slug mapping for facility: %s", name)
            continue

        facilities.append(
            DiscoveredFacility(
                name=name,
                address=address,
                region=current_region,
                slug=slug,
                url=FACILITY_URL_TEMPLATE.format(slug=slug),
            )
        )

    logger.info("Discovered %d facilities", len(facilities))
    return facilities
