# AI-generated content: this file contains code generated with the help of artificial intelligence (Claude, Anthropic).
# Contenido generado con IA: este archivo contiene código generado con ayuda de inteligencia artificial (Claude, Anthropic).
"""Typed, bilingual errors so the UI can tell 'no data' apart from 'error'."""
from __future__ import annotations


class AnalysisError(Exception):
    """An expected failure with a user-facing explanation in ES and EN.

    kind:
      - invalid_input: the selection or parameters cannot be analysed.
      - no_data: the provider has no usable observations for this area/period.
      - provider_error: an external provider failed or answered badly.
      - not_configured: credentials or settings are missing on the server.
      - timeout: the analysis exceeded the time limit.
    """

    def __init__(self, kind: str, es: str, en: str, *, retryable: bool = False):
        super().__init__(es)
        self.kind = kind
        self.es = es
        self.en = en
        self.retryable = retryable

    def to_dict(self) -> dict:
        return {"kind": self.kind, "message": {"es": self.es, "en": self.en}, "retryable": self.retryable}


def no_data(es: str, en: str) -> AnalysisError:
    return AnalysisError("no_data", es, en)


def invalid(es: str, en: str) -> AnalysisError:
    return AnalysisError("invalid_input", es, en)


def provider(es: str, en: str) -> AnalysisError:
    return AnalysisError("provider_error", es, en, retryable=True)


def not_configured(es: str, en: str) -> AnalysisError:
    return AnalysisError("not_configured", es, en)
