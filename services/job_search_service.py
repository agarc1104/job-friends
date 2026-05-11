from __future__ import annotations

from typing import Any

import serpapi

from backend_config import settings


def search_google_jobs(
    keywords: str,
    city: str = "",
    region: str = "",
    country_name: str = "",
    *,
    location: str = "",
    hl: str = "",
    gl: str = "",
    google_domain: str = "",
) -> list[dict[str, Any]]:
    if not settings.serpapi_api_key:
        return []

    normalized_keywords = keywords.strip()
    if not normalized_keywords:
        return []

    client = serpapi.Client(api_key=settings.serpapi_api_key)
    params = {
        "engine": "google_jobs",
        "q": normalized_keywords,
    }

    explicit_location = location.strip()
    if explicit_location:
        params["location"] = explicit_location
    else:
        location_parts = [city.strip(), region.strip(), country_name.strip()]
        location_parts = [part for part in location_parts if part]
        normalized_parts: list[str] = []
        seen_parts: set[str] = set()
        for part in location_parts:
            normalized_key = part.lower()
            if normalized_key in seen_parts:
                continue
            seen_parts.add(normalized_key)
            normalized_parts.append(part)
        if normalized_parts:
            params["location"] = ", ".join(normalized_parts)

    normalized_hl = hl.strip().lower()
    normalized_gl = gl.strip().lower()
    normalized_domain = google_domain.strip().lower()

    if len(normalized_hl) == 2:
        params["hl"] = normalized_hl
    if len(normalized_gl) == 2:
        params["gl"] = normalized_gl
    if normalized_domain:
        params["google_domain"] = normalized_domain

    try:
        results = client.search(params)
    except Exception:
        return []

    jobs = results.get("jobs_results", [])
    return jobs if isinstance(jobs, list) else []