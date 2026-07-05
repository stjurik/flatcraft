"""Тести Sentry PII-фільтра й no-op ініціалізації (ADR-032, CLAUDE.md §8)."""

from __future__ import annotations

import pytest

from flatcraft_cad.sentry_setup import init_sentry, redact_pii


def test_redact_pii_strips_user_email_ip_username() -> None:
    event = {"user": {"id": "u1", "email": "a@b.c", "ip_address": "1.2.3.4", "username": "a@b.c"}}
    out = redact_pii(event, {})
    assert out["user"] == {"id": "u1"}


def test_redact_pii_strips_cookies_query_and_sensitive_headers() -> None:
    event = {
        "request": {
            "cookies": {"s": "x"},
            "query_string": "email=a@b.c",
            "headers": {"Authorization": "Bearer x", "Cookie": "a=b", "User-Agent": "UA"},
        }
    }
    out = redact_pii(event, {})
    assert "cookies" not in out["request"]
    assert "query_string" not in out["request"]
    assert out["request"]["headers"] == {"User-Agent": "UA"}


def test_redact_pii_noop_without_user_request() -> None:
    assert redact_pii({"level": "error"}, {})["level"] == "error"


def test_init_sentry_noop_without_dsn(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("SENTRY_DSN", raising=False)
    assert init_sentry() is False
