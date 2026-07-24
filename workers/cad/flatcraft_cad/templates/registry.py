"""Template Registry (ADR-033 §2, §5) — паритет з TS `packages/templates/src/registry.ts`.

Ручний dict (ADR-033 §5 ALT-A, обрано над `__init_subclass__` автореєстрацією):
явний import — якщо шаблон не імпортовано сюди, він не зареєстрований, і
parity-тест (`tests/templates/test_registry.py`) негайно падає (F6-клас бага:
`enclosed_shelf`, що колись випав з `templates/__init__.py.__all__`).

Run 7 Master Registry Track, Етап 2: кожен PR додає РІВНО один
`"<slug>": <Slug>Template` запис (порядок — docs/12 §6: perforated_panel →
corner_angle → l_bracket → z_bracket → wall_shelf → enclosed_shelf).
"""

from typing import Any

from flatcraft_cad.templates.base import Template
from flatcraft_cad.templates.corner_angle import CornerAngleTemplate
from flatcraft_cad.templates.perforated_panel import PerforatedPanelTemplate

TEMPLATES: dict[str, type[Template[Any]]] = {
    "perforated_panel": PerforatedPanelTemplate,
    "corner_angle": CornerAngleTemplate,
}
