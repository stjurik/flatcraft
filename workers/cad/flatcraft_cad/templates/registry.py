"""Template Registry (ADR-033 §2, §5) — паритет з TS `packages/templates/src/registry.ts`.

Ручний dict (ADR-033 §5 ALT-A, обрано над `__init_subclass__` автореєстрацією):
явний import — якщо шаблон не імпортовано сюди, він не зареєстрований, і
parity-тест (`tests/templates/test_registry.py`) негайно падає (F6-клас бага:
`enclosed_shelf`, що колись випав з `templates/__init__.py.__all__`).

ПОКИ ПОРОЖНІЙ (Run 7 Master Registry Track, Етап 1): `docs/12_TEMPLATE_CONTRACT.md`
§6 фіксує це PR як registry-скафолдинг без міграції жодного шаблону. Кожен
наступний PR Етапу 2 додає РІВНО один `"<slug>": <Slug>Template` запис.
"""

from typing import Any

from flatcraft_cad.templates.base import Template

TEMPLATES: dict[str, type[Template[Any]]] = {}
