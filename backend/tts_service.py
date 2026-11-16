"""Text-to-speech with Gemini: reads the computed summary + the Gemini interpretation.

Gemini TTS returns raw 16-bit PCM (mime like ``audio/L16;codec=pcm;rate=24000``); it is
wrapped in a WAV container so every browser can play it. The text is built on the server
from the same result and locale shown on screen, so audio and text never diverge.
Audio is cached per (result, locale) to avoid paying twice for the same reading.
"""
from __future__ import annotations

import io
import os
import re
import threading
import time
import wave
from collections import OrderedDict

from errors import AnalysisError, not_configured

PREFERRED_MODELS = (
    "gemini-3.8-flash-tts",
    "gemini-3.1-flash-tts-preview",
    "gemini-2.5-flash-preview-tts",
)
VOICES = {"es": os.getenv("GEMINI_TTS_VOICE_ES", "Kore"), "en": os.getenv("GEMINI_TTS_VOICE_EN", "Kore")}
STYLE = {
    "es": "Lee en español, con voz clara, cálida y pausada, como una persona que explica resultados a otra:",
    "en": "Read in English, with a clear, warm and unhurried voice, like someone explaining results to another person:",
}
MAX_CHARS = 3800

_model_lock = threading.Lock()
_model: dict[str, str | None] = {"name": None}
_cache: OrderedDict[tuple, tuple[float, bytes]] = OrderedDict()
_cache_lock = threading.Lock()


def build_parts(result: dict, interpretation: dict | None, locale: str) -> list[str]:
    """Part 0: computed summary (fast to generate, plays first). Part 1: Gemini explanation."""
    parts = [result.get("summary", {}).get(locale, {}).get("speech", "")]
    if interpretation and interpretation.get("locale") == locale:
        a = interpretation.get("answer", {})
        intro = "Explicación de la inteligencia artificial." if locale == "es" else "Explanation from the artificial intelligence."
        cannot = "Lo que no se puede concluir:" if locale == "es" else "What cannot be concluded:"
        texts = [intro, a.get("summary", ""), a.get("pattern", ""), a.get("meaning", "")]
        if a.get("cannot_conclude"):
            texts += [cannot, *a["cannot_conclude"]]
        parts.append(" ".join(t.strip() for t in texts if t and t.strip()))
    return [re.sub(r"\s+", " ", p).strip()[:MAX_CHARS] for p in parts]


def build_text(result: dict, interpretation: dict | None, locale: str) -> str:
    return " ".join(build_parts(result, interpretation, locale))


def pcm_to_wav(pcm: bytes, rate: int = 24000, channels: int = 1, width: int = 2) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(width)
        w.setframerate(rate)
        w.writeframes(pcm)
    return buf.getvalue()


def _rate(mime: str | None) -> int:
    m = re.search(r"rate=(\d+)", mime or "")
    return int(m.group(1)) if m else 24000


def _pick_model(client, settings) -> str:
    with _model_lock:
        if _model["name"]:
            return _model["name"]
        wanted = os.getenv("GEMINI_TTS_MODEL", "").strip()
        try:
            names = [m.name.split("/")[-1] for m in client.models.list()]
        except Exception:
            names = []
        tts = [n for n in names if "tts" in n]
        choice = None
        if wanted and (not names or wanted in names):
            choice = wanted
        else:
            choice = next((p for p in PREFERRED_MODELS if p in tts), tts[0] if tts else None)
        if not choice:
            raise AnalysisError(
                "not_configured",
                "La clave de Gemini no tiene acceso a ningún modelo de voz (TTS). Se usará la voz del navegador.",
                "The Gemini key has no access to any speech (TTS) model. The browser voice will be used.",
            )
        _model["name"] = choice
        return choice


def synthesize(result: dict, interpretation: dict | None, locale: str, settings, *, part: int = 0,
               client=None) -> tuple[bytes, dict]:
    if not settings.gemini_configured:
        raise not_configured(
            "La voz de Gemini no está configurada (falta GEMINI_API_KEY). Se usará la voz del navegador.",
            "Gemini voice is not configured (GEMINI_API_KEY missing). The browser voice will be used.",
        )
    parts = build_parts(result, interpretation, locale)
    if part >= len(parts) or not parts[part]:
        raise AnalysisError("no_data", "No hay más texto para leer.", "There is no more text to read.")
    text = parts[part]
    key = (result.get("result_id"), locale, part, hash(text))
    with _cache_lock:
        hit = _cache.get(key)
        if hit:
            _cache.move_to_end(key)
            return hit[1], {"cached": True, "model": _model["name"], "chars": len(text), "parts": len(parts)}

    from google import genai
    from google.genai import types

    client = client or genai.Client(
        api_key=settings.gemini_api_key,
        # TTS models are published on v1beta (not on the stable v1 listing).
        http_options=types.HttpOptions(api_version="v1beta", timeout=int(max(settings.gemini_timeout_seconds, 60) * 1000)),
    )
    model = _pick_model(client, settings)
    try:
        resp = client.models.generate_content(
            model=model,
            contents=f"{STYLE[locale]}\n\n{text}",
            config=types.GenerateContentConfig(
                response_modalities=["AUDIO"],
                speech_config=types.SpeechConfig(
                    voice_config=types.VoiceConfig(
                        prebuilt_voice_config=types.PrebuiltVoiceConfig(voice_name=VOICES[locale]),
                    ),
                ),
            ),
        )
        part = resp.candidates[0].content.parts[0].inline_data
        pcm = part.data
        if isinstance(pcm, str):  # some SDK versions return base64 text
            import base64

            pcm = base64.b64decode(pcm)
        if not pcm:
            raise ValueError("empty audio")
        mime = part.mime_type or ""
        audio = pcm if "wav" in mime else pcm_to_wav(pcm, _rate(mime))
    except AnalysisError:
        raise
    except Exception as e:  # quota, model, network — never leak key or raw error to the client
        raise AnalysisError(
            "provider_error",
            "Gemini no pudo generar el audio ahora. Se usará la voz del navegador; puedes reintentarlo más tarde.",
            "Gemini could not generate the audio right now. The browser voice will be used; try again later.",
            retryable=True,
        ) from e
    with _cache_lock:
        _cache[key] = (time.time(), audio)
        total = sum(len(v[1]) for v in _cache.values())
        while _cache and (len(_cache) > 20 or total > 60 * 1024 * 1024):
            _, (_, old) = _cache.popitem(last=False)
            total -= len(old)
    return audio, {"cached": False, "model": model, "chars": len(text), "parts": len(parts)}
