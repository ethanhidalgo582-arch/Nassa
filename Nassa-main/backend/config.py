import os
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv


@dataclass(frozen=True)
class Settings:
    gemini_api_key: str = field(default="", repr=False)
    gemini_model: str = "gemini-3.5-flash-lite"
    gemini_timeout_seconds: float = 40
    cors_origins: tuple[str, ...] = ("http://localhost:3000", "http://127.0.0.1:3000")

    @classmethod
    def from_env(cls):
        load_dotenv(Path(__file__).with_name(".env"), override=False)
        timeout = float(os.getenv("GEMINI_TIMEOUT_SECONDS", "40"))
        if not 1 <= timeout <= 50:
            raise ValueError("GEMINI_TIMEOUT_SECONDS debe estar entre 1 y 50.")
        model = os.getenv("GEMINI_MODEL", "gemini-3.5-flash-lite").strip()
        if not model:
            raise ValueError("GEMINI_MODEL no puede estar vacío.")
        return cls(
            gemini_api_key=os.getenv("GEMINI_API_KEY", "").strip(),
            gemini_model=model,
            gemini_timeout_seconds=timeout,
            cors_origins=tuple(
                origin.strip()
                for origin in os.getenv("CORS_ORIGINS", "http://localhost:3000,http://127.0.0.1:3000").split(",")
                if origin.strip()
            ),
        )
