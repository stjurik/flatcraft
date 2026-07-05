"""Sentry-ініціалізація CAD-воркера (ADR-032, Roadmap 5.1).

No-op без ``SENTRY_DSN`` (dev / CI / тести не чіпаються). Sample: errors 100% /
traces 0 (ресурси MS21). ``before_send`` прибирає PII (email / IP / чутливі
заголовки) — інваріант CLAUDE.md §8, паритет pino-redact у api.
"""

from __future__ import annotations

import os
from typing import Any, cast

import sentry_sdk

_SENSITIVE_HEADER_KEYS = frozenset({"authorization", "cookie", "set-cookie", "x-csrf-token"})
_PII_USER_KEYS = ("email", "ip_address", "username")


def redact_pii(event: dict[str, Any], _hint: dict[str, Any]) -> dict[str, Any]:
    """``before_send``: прибирає PII з події ПЕРЕД відправкою у Sentry."""
    user = event.get("user")
    if isinstance(user, dict):
        for key in _PII_USER_KEYS:
            user.pop(key, None)
    request = event.get("request")
    if isinstance(request, dict):
        request.pop("cookies", None)
        request.pop("query_string", None)
        headers = request.get("headers")
        if isinstance(headers, dict):
            for key in list(headers):
                if key.lower() in _SENSITIVE_HEADER_KEYS:
                    headers.pop(key, None)
    return event


def init_sentry() -> bool:
    """Ініціалізує Sentry, якщо заданий ``SENTRY_DSN``. Повертає, чи ініціалізовано."""
    dsn = os.environ.get("SENTRY_DSN")
    if not dsn:
        return False
    sentry_sdk.init(
        dsn=dsn,
        environment=os.environ.get("SENTRY_ENVIRONMENT", "production"),
        traces_sample_rate=0.0,
        send_default_pii=False,
        # redact_pii типізовано як dict[str, Any]; Sentry чекає Event TypedDict —
        # структурно сумісні у рантаймі, каст лише для type-checker'а.
        before_send=cast("Any", redact_pii),
    )
    return True
