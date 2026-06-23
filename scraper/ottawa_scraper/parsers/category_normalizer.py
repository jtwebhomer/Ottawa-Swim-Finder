"""Normalize swim category labels from Ottawa.ca."""

from __future__ import annotations

CANONICAL_CATEGORIES = {
    "general_swim",
    "lane_swim",
    "family_swim",
    "parent_tot",
    "aquafit",
    "adult_swim",
    "womens_swim",
    "therapeutic_swim",
    "wave_swim",
    "preschool_swim",
    "other",
}


def _contains_any(haystack: str, needles: tuple[str, ...]) -> bool:
    return any(n in haystack for n in needles)


def normalize_category(raw: str) -> str:
    lower = raw.lower().strip()

    if _contains_any(lower, ("parent & tot", "parent and tot", "parent/tot")):
        return "parent_tot"
    if _contains_any(lower, ("women", "women's", "womens", "female only")):
        return "womens_swim"
    if _contains_any(lower, ("preschool", "pre-school")):
        return "preschool_swim"
    if _contains_any(lower, ("lane swim", "adult lane", "fitness swim", "length swim")):
        return "lane_swim"
    if _contains_any(lower, ("aquafit", "aqua fit", "aquafitness", "aqua-fit")):
        return "aquafit"
    if _contains_any(lower, ("aqua therapy", "aquatic therapy", "therapeutic", "therapy swim")):
        return "therapeutic_swim"
    if "family" in lower:
        return "family_swim"
    if _contains_any(lower, ("adult swim", "adults only swim", "adult only")):
        return "adult_swim"
    if _contains_any(
        lower,
        (
            "public swim",
            "leisure swim",
            "recreation swim",
            "rec swim",
            "open swim",
            "general swim",
            "alternate needs swim",
            "accessibility swim",
            "accessible swim",
        ),
    ):
        return "general_swim"
    if _contains_any(lower, ("wave swim", "wave tank")) or lower == "wave":
        return "wave_swim"
    if "swim" in lower:
        return "general_swim"
    return "other"


def is_swim_row(raw: str) -> bool:
    if normalize_category(raw) != "other":
        return True
    lower = raw.lower()
    return any(
        kw in lower
        for kw in ("swim", "aquafit", "aqua fit", "aqua therapy", "hot tub", "wave")
    )
