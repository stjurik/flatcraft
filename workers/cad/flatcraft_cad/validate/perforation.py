"""Parity perforation-валідатор (дзеркало TS validators/perforation.ts).

Геометрична коректність grid отворів перфо-панелі: крок (pitch) має бути
більший за розмір отвору по кожній осі, інакше сусідні отвори торкаються/
перетинаються і зливаються у суцільний проріз (а BOM рахує їх як N окремих
отворів — невідповідність заготовки).

Правило (паритет з TS):
    pitch > hole_size   → валідно
    pitch <= hole_size  → HOLES_OVERLAP

де hole_size — сторона квадрата (perforated_panel_square) або діаметр
(perforated_panel). Остання лінія оборони у воркері — навіть якщо API-gate
обійдено, відмова ДО CAD-операції/запису у R2 з 422 RFC 9457.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any

_AXIS_LABEL = {
    "pitch_x_mm": "Крок X",
    "pitch_y_mm": "Крок Y",
}


@dataclass(frozen=True)
class PerforationError:
    """Один елемент 422-detail. `code` збігається з кодом TS-валідатора."""

    code: str
    field: str
    detail: str


def _fmt(n: float) -> str:
    return f"{round(n, 3):g}"


def _overlap_msg(which: str, pitch: float, hole_size: float, shape_word: str) -> str:
    return (
        f"Збільшіть «{_AXIS_LABEL.get(which, which)}»: крок {_fmt(pitch)} мм має бути "
        f"більший за {shape_word} отвору {_fmt(hole_size)} мм — інакше сусідні отвори "
        "перетинаються."
    )


def validate_perforation(
    template_slug: str,
    parameters: dict[str, Any],
) -> list[PerforationError]:
    """Перевіряє grid перфорації. Порожній список → валідно.

    Невідомий slug або невизначений/непозитивний розмір отвору → [] (останнє
    відсіється Pydantic-діапазонами окремо).
    """
    if template_slug == "perforated_panel_square":
        hole_size = parameters.get("hole_size_mm")
        shape_word = "сторону"
    elif template_slug == "perforated_panel":
        hole_size = parameters.get("hole_diameter_mm")
        shape_word = "діаметр"
    else:
        return []

    if hole_size is None or hole_size <= 0:
        return []

    errors: list[PerforationError] = []
    for which in ("pitch_x_mm", "pitch_y_mm"):
        pitch = parameters.get(which)
        if pitch is None:
            continue
        # Валідно при pitch > hole_size. pitch <= hole_size → торкання/перетин.
        if pitch <= hole_size:
            errors.append(
                PerforationError(
                    code="HOLES_OVERLAP",
                    field=which,
                    detail=_overlap_msg(which, float(pitch), float(hole_size), shape_word),
                )
            )
    return errors


def validate_export_perforation(
    template_slug: str,
    parameters: dict[str, Any],
) -> list[dict[str, str]]:
    """JSON-готовий список dict-ів для 422-detail (паритет з validate_export)."""
    return [asdict(e) for e in validate_perforation(template_slug, parameters)]
