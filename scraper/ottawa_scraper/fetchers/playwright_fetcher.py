"""Playwright fallback fetcher for JS-rendered pages."""

from __future__ import annotations

import hashlib
import logging

from .http_fetcher import FetchResult

logger = logging.getLogger(__name__)


class PlaywrightFetcher:
  def fetch(self, url: str) -> FetchResult:
    try:
      from playwright.sync_api import sync_playwright
    except ImportError as exc:
      raise RuntimeError("Playwright not installed") from exc

    with sync_playwright() as p:
      browser = p.chromium.launch(headless=True)
      page = browser.new_page()
      page.goto(url, wait_until="networkidle", timeout=60000)
      html = page.content()
      browser.close()

    content_hash = hashlib.sha256(html.encode("utf-8")).hexdigest()
    return FetchResult(
        url=url,
        html=html,
        content_hash=content_hash,
        status_code=200,
        fetcher="playwright",
    )
