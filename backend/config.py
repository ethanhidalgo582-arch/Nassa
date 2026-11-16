# AI-generated content: this file contains code generated with the help of artificial intelligence (Claude, Anthropic).
# Contenido generado con IA: este archivo contiene código generado con ayuda de inteligencia artificial (Claude, Anthropic).
"""Runtime configuration read from environment variables.

Secrets (GEMINI_API_KEY, EARTHDATA_*) are only read here, on the server.
They are never returned by any endpoint nor written to logs.
"""
from __future__ import annotations

import os
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv

BACKEND_DIR = Path(__file__).resolve().parent
APP_NAME = "IMPACT"
APP_VERSION = "1.0.0"


def _int(name: str, default: int, lo: int, hi: int) -> int:
    try:
        value = int(os.getenv(name, str(default)))
    except ValueError:
        return default
    return max(lo, min(hi, value))


def _float(name: str, default: float, lo: float, hi: float) -> float:
    try:
        value = float(os.getenv(name, str(default)))
    except ValueError:
        return default
    return max(lo, min(hi, value))


@dataclass(frozen=True)
class Settings:
    gemini_api_key: str = field(default="", repr=False)
    gemini_model: str = "gemini-3.5-flash-lite"
    gemini_timeout_seconds: float = 40.0

    earthdata_username: str = ""
    earthdata_password: str = field(default="", repr=False)
    earthdata_token: str = field(default="", repr=False)
    nisar_collections: tuple[str, ...] = ("NISAR_L2_GUNW_V1", "NISAR_L2_GUNW_PROVISIONAL_V1")
    nisar_max_pairs: int = 6
    nisar_access_mode: str = "stream"  # stream (HTTP range reads) | download
    nisar_live_budget_seconds: int = 30  # wait this long for live data before using the saved backup

    allowed_origins: tuple[str, ...] = ()
    public_app_url: str = ""
    carto_api_key: str = ""  # public, domain-restricted tile key (optional)

    cache_dir: Path = Path(tempfile.gettempdir()) / "impact-cache"
    max_concurrent_jobs: int = 1
    job_timeout_seconds: int = 900
    result_ttl_seconds: int = 6 * 3600
    max_forest_pixels: int = 12_000_000
    max_area_km2: float = 20_000.0

    @property
    def gemini_configured(self) -> bool:
        return bool(self.gemini_api_key)

    @property
    def earthdata_configured(self) -> bool:
        return bool(self.earthdata_token or (self.earthdata_username and self.earthdata_password))

    @classmethod
    def from_env(cls) -> "Settings":
        load_dotenv(BACKEND_DIR / ".env", override=False)
        origins = tuple(
            o.strip().rstrip("/")
            for o in os.getenv("ALLOWED_ORIGINS", "").split(",")
            if o.strip()
        )
        collections = tuple(
            c.strip()
            for c in os.getenv("NISAR_COLLECTIONS", "NISAR_L2_GUNW_V1,NISAR_L2_GUNW_PROVISIONAL_V1").split(",")
            if c.strip()
        )
        mode = os.getenv("NISAR_ACCESS_MODE", "stream").strip().lower()
        return cls(
            gemini_api_key=os.getenv("GEMINI_API_KEY", "").strip(),
            gemini_model=os.getenv("GEMINI_MODEL", "gemini-3.5-flash-lite").strip() or "gemini-3.5-flash-lite",
            gemini_timeout_seconds=_float("GEMINI_TIMEOUT_SECONDS", 40, 5, 120),
            earthdata_username=os.getenv("EARTHDATA_USERNAME", "").strip(),
            earthdata_password=os.getenv("EARTHDATA_PASSWORD", "").strip(),
            earthdata_token=os.getenv("EARTHDATA_TOKEN", "").strip(),
            nisar_collections=collections or ("NISAR_L2_GUNW_V1",),
            nisar_max_pairs=_int("NISAR_MAX_PAIRS", 6, 1, 30),
            nisar_access_mode=mode if mode in ("stream", "download") else "stream",
            nisar_live_budget_seconds=_int("NISAR_LIVE_BUDGET_SECONDS", 30, 5, 3600),
            allowed_origins=origins,
            public_app_url=os.getenv("PUBLIC_APP_URL", "").strip().rstrip("/"),
            carto_api_key=os.getenv("CARTO_API_KEY", "").strip(),
            cache_dir=Path(os.getenv("CACHE_DIR", str(Path(tempfile.gettempdir()) / "impact-cache"))),
            max_concurrent_jobs=_int("MAX_CONCURRENT_JOBS", 1, 1, 8),
            job_timeout_seconds=_int("JOB_TIMEOUT_SECONDS", 900, 30, 3600),
            result_ttl_seconds=_int("RESULT_TTL_SECONDS", 6 * 3600, 300, 7 * 24 * 3600),
            max_forest_pixels=_int("MAX_FOREST_PIXELS", 12_000_000, 100_000, 100_000_000),
            max_area_km2=_float("MAX_AREA_KM2", 20_000, 1, 1_000_000),
        )


def user_agent(settings: Settings) -> str:
    """Identifying User-Agent for third-party APIs (no personal data)."""
    contact = settings.public_app_url or "https://github.com"
    return f"{APP_NAME}/{APP_VERSION} (+{contact})"
