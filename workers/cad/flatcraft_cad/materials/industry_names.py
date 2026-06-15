"""Industry-standard назви матеріалів для креслень (Hotfix 2.9.d).

Проблема: у BOM PDF матеріал друкувався slug'ом (`cold_rolled_steel`) —
виробник лазерного різання не розуміє, що замовляти. Тут — мапа slug →
(марка, стандарт, українська назва), щоб BOM показував, напр.:

    DC01 (ДСТУ EN 10130) — холоднокатана сталь

Pure-модуль без залежностей від PDF/ezdxf — легко юніт-тестувати.
Невідомий код → fallback на сирий slug + WARNING у лог (експорт не падає).
"""

from __future__ import annotations

import logging
from dataclasses import dataclass
from typing import Final

logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class MaterialIndustryName:
    """Industry-назва матеріалу для креслення.

    `name` — марка/позначення (DC01, AISI 304, АМг3); `standard` — нормативний
    документ (ДСТУ EN 10130); `ukrainian_name` — побутова українська назва.
    """

    name: str
    standard: str
    ukrainian_name: str


# slug (material_code з seed/CLAUDE.md §7) → industry-назва. Марки і стандарти
# узгоджено з CLAUDE.md §7 (матеріали MVP). copper/brass — поза seed MVP, але
# у §7-списку, тож тримаємо мапу повною (forward-сумісність).
_INDUSTRY_NAMES: Final[dict[str, MaterialIndustryName]] = {
    "cold_rolled_steel": MaterialIndustryName("DC01", "ДСТУ EN 10130", "холоднокатана сталь"),
    "hot_rolled_steel": MaterialIndustryName("S235JR", "ДСТУ EN 10025-2", "гарячекатана сталь"),
    "galvanized_steel": MaterialIndustryName("DX51D+Z", "ДСТУ EN 10346", "оцинкована сталь"),
    "stainless_304": MaterialIndustryName("AISI 304", "ДСТУ EN 10088-2", "нержавіюча сталь"),
    "stainless_430": MaterialIndustryName("AISI 430", "ДСТУ EN 10088-2", "нержавіюча сталь"),
    "aluminum_amg3": MaterialIndustryName("АМг3", "ДСТУ 4400-86", "алюмінієвий сплав"),
    "aluminum_5754": MaterialIndustryName("5754-H22", "EN 573-3", "алюмінієвий сплав"),
    "copper": MaterialIndustryName("М1", "ДСТУ ГОСТ 859", "мідь"),
    "brass": MaterialIndustryName("Л63", "ДСТУ ГОСТ 15527", "латунь"),
}


def industry_name(material_code: str) -> MaterialIndustryName | None:
    """Industry-назва для slug'а матеріалу, або `None` для невідомого коду.

    Pure-функція: жодних side-effects (логування — у `format_material_label`,
    де ухвалюється рішення про fallback)."""
    return _INDUSTRY_NAMES.get(material_code)


def format_material_label(material_code: str) -> str:
    """Рядок матеріалу для BOM: `DC01 (ДСТУ EN 10130) — холоднокатана сталь`.

    Якщо код невідомий — повертає сирий код і пише WARNING (експорт не падає,
    але сигналізує, що довідник треба доповнити)."""
    info = industry_name(material_code)
    if info is None:
        logger.warning("Невідомий material_code %r — BOM покаже сирий код", material_code)
        return material_code
    return f"{info.name} ({info.standard}) — {info.ukrainian_name}"
