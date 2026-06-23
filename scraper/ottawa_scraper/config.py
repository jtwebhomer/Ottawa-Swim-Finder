"""Configuration for Ottawa scraper."""

from pathlib import Path

BASE_URL = "https://ottawa.ca"
INDOOR_POOLS_URL = (
    f"{BASE_URL}/en/drop-swimming-and-aquafitness/indoor-pools-drop-locations"
)
FACILITY_URL_TEMPLATE = (
    f"{BASE_URL}/en/recreation-and-parks/facilities/place-listing/{{slug}}"
)

USER_AGENT = (
    "Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36"
)
REQUEST_TIMEOUT = 30
MAX_RETRIES = 3

SNAPSHOTS_DIR = Path(__file__).parent / "snapshots"
SNAPSHOTS_DIR.mkdir(exist_ok=True)

# Known slug mappings for facilities (name fragment -> slug)
FACILITY_SLUGS: dict[str, str] = {
    "brewer pool": "brewer-pool-and-arena",
    "champagne fitness": "champagne-fitness-centre",
    "jack purcell": "jack-purcell-community-centre",
    "lowertown": "lowertown-community-centre-and-pool",
    "plant recreation": "plant-recreation-centre",
    "bob macquarrie": "bob-macquarrie-recreation-complex-orleans",
    "canterbury": "canterbury-recreation-complex",
    "françois dupuis": "francois-dupuis-recreation-centre",
    "francois dupuis": "francois-dupuis-recreation-centre",
    "ray friel": "ray-friel-recreation-complex",
    "splash wave": "splash-wave-pool",
    "st. laurent": "st-laurent-complex",
    "st-laurent": "st-laurent-complex",
    "deborah anne kirwan": "deborah-anne-kirwan-pool",
    "sawmill creek": "sawmill-creek-community-centre-and-pool",
    "nepean sportsplex": "nepean-sportsplex",
    "walter baker": "walter-baker-sports-centre",
    "cardelrec": "cardelrec-recreation-complex-goulbourn",
    "kanata leisure": "kanata-leisure-centre-and-wave-pool",
    "minto recreation": "minto-recreation-complex-barrhaven",
    "pinecrest": "pinecrest-recreation-complex",
    "richcraft": "richcraft-recreation-complex-kanata",
}

SWIM_KEYWORDS = (
    "lane swim",
    "public swim",
    "family swim",
    "aquafit",
    "women",
    "therapeutic",
    "open swim",
    "wave swim",
    "preschool swim",
    "hot tub",
)
