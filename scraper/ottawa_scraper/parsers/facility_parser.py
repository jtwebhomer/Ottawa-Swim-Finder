"""Parse facility metadata from page HTML."""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass

from bs4 import BeautifulSoup

logger = logging.getLogger(__name__)

# Pre-seeded coordinates for Ottawa pool facilities
COORDINATES: dict[str, tuple[float, float]] = {
    "brewer-pool-and-arena": (45.3889, -75.6889),
    "champagne-fitness-centre": (45.4290, -75.6780),
    "jack-purcell-community-centre": (45.4180, -75.6890),
    "lowertown-community-centre-and-pool": (45.4280, -75.6880),
    "plant-recreation-centre": (45.4090, -75.6990),
    "bob-macquarrie-recreation-complex-orleans": (45.4760, -75.5160),
    "canterbury-recreation-complex": (45.3520, -75.6680),
    "francois-dupuis-recreation-centre": (45.4670, -75.5120),
    "ray-friel-recreation-complex": (45.4670, -75.4680),
    "splash-wave-pool": (45.4360, -75.5980),
    "st-laurent-complex": (45.4380, -75.6380),
    "deborah-anne-kirwan-pool": (45.3580, -75.6480),
    "sawmill-creek-community-centre-and-pool": (45.3680, -75.6980),
    "nepean-sportsplex": (45.3380, -75.7580),
    "walter-baker-sports-centre": (45.2780, -75.7580),
    "cardelrec-recreation-complex-goulbourn": (45.2580, -75.9180),
    "kanata-leisure-centre-and-wave-pool": (45.3080, -75.9180),
    "minto-recreation-complex-barrhaven": (45.2780, -75.7580),
    "pinecrest-recreation-complex": (45.3480, -75.7580),
    "richcraft-recreation-complex-kanata": (45.2980, -75.8980),
}


@dataclass
class ParsedFacility:
    name: str
    address: str | None
    postal_code: str | None
    phone: str | None
    latitude: float | None
    longitude: float | None


def parse_facility(html: str, slug: str, fallback_name: str, fallback_address: str) -> ParsedFacility:
    soup = BeautifulSoup(html, "lxml")

    name = fallback_name
    h1 = soup.find("h1")
    if h1:
        name = h1.get_text(strip=True)

    address = fallback_address
    postal_code = None
    phone = None

    page_text = soup.get_text(" ", strip=True)
    postal_match = re.search(r"Ottawa\s+ON\s+([A-Z]\d[A-Z]\s*\d[A-Z]\d)", page_text)
    if postal_match:
        postal_code = postal_match.group(1)

    phone_match = re.search(r"Tel:\s*([\d\-]+)", page_text)
    if phone_match:
        phone = phone_match.group(1)

    lat, lng = COORDINATES.get(slug, (None, None))

    return ParsedFacility(
        name=name,
        address=address,
        postal_code=postal_code,
        phone=phone,
        latitude=lat,
        longitude=lng,
    )
