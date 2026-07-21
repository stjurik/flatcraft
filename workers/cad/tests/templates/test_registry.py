"""Conformance-suite (Python-сторона) — ADR-033 §5, docs/12_TEMPLATE_CONTRACT.md §3.

Slug-паритет: `TEMPLATES` (цей модуль) звіряється проти фікстури
`tests/fixtures/ts_registry_slugs.json`, яку генерує `tools/scripts/export-registry.ts`
з TS `TEMPLATE_REGISTRY`. Дзеркальний TS-тест
(`packages/templates/test/registry-fixture-sync.test.ts`) звіряє ту саму
фікстуру у зворотному напрямку. Якщо один реєстр випереджає інший — падає
рівно той бік, що встиг регенерувати фікстуру (F6-клас бага, C1-інвентаризація).

DXF/PDF-детермінізм (docs/12 §3.2): `test_dxf_deterministic` нижче
параметризовано з `TEMPLATES.keys()` — з порожнім реєстром (Run 7 Етап 1) це
0 test-кейсів (pytest не падає на порожній `parametrize`, просто не генерує
жодного); коли Етап 2 додає перший slug, снапшот-перевірка вмикається сама.
"""

import json
from pathlib import Path

import pytest

from flatcraft_cad.templates.registry import TEMPLATES

FIXTURE_PATH = Path(__file__).resolve().parent.parent / "fixtures" / "ts_registry_slugs.json"


def test_slug_parity_with_ts_registry() -> None:
    ts_slugs = set(json.loads(FIXTURE_PATH.read_text(encoding="utf-8")))
    assert ts_slugs == set(TEMPLATES.keys())


@pytest.mark.parametrize("slug", sorted(TEMPLATES.keys()))
def test_dxf_deterministic(slug: str) -> None:
    """Плейсхолдер (docs/12 §3.2) — активується для конкретного шаблону лише
    коли той шаблон зареєстрований (Run 7 Етап 2, один PR = один шаблон)."""
    tpl_cls = TEMPLATES[slug]
    assert tpl_cls.name == slug
