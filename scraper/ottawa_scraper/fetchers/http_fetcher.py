"""HTTP fetcher with retries."""

from __future__ import annotations

import hashlib
import logging
import time
from dataclasses import dataclass

import requests

from ..config import MAX_RETRIES, REQUEST_TIMEOUT, USER_AGENT

logger = logging.getLogger(__name__)


@dataclass
class FetchResult:
    url: str
    html: str
    content_hash: str
    status_code: int
    fetcher: str = "requests"


class HttpFetcher:
    def __init__(self) -> None:
        self.session = requests.Session()
        self.session.headers.update({
            "User-Agent": USER_AGENT,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-CA,en;q=0.9",
        })

    def fetch(self, url: str) -> FetchResult:
        last_error: Exception | None = None
        for attempt in range(1, MAX_RETRIES + 1):
            try:
                response = self.session.get(url, timeout=REQUEST_TIMEOUT)
                response.raise_for_status()
                html = response.text
                content_hash = hashlib.sha256(html.encode("utf-8")).hexdigest()
                return FetchResult(
                    url=url,
                    html=html,
                    content_hash=content_hash,
                    status_code=response.status_code,
                )
            except Exception as exc:
                last_error = exc
                logger.warning("Fetch attempt %s failed for %s: %s", attempt, url, exc)
                time.sleep(attempt)
        raise RuntimeError(f"Failed to fetch {url}") from last_error
