"""Parity hole-to-bend-distance валідатор (docs/07 §3, рішення yurii 2026-10-11).

Дзеркало TS `packages/cad-engine/src/validators/holes.ts` +
`export-gate.ts::validateExportHoles`. Правило вимірюється від НАЙБЛИЖЧОГО
КРАЮ отвору до лінії гиба (>= a·t+R), але поле `distance_from_bend_mm` у
Zod/Pydantic-схемі й студії — від ЦЕНТРУ отвору (UX). Перераховуємо
центр → край ТУТ, в одному місці, перед порівнянням з мінімумом.

Лише l_bracket і z_bracket мають поле `holes[].distance_from_bend_mm`
(corner_angle/wall_shelf — auto-grid без цього поля; perforated_panel/
enclosed_shelf — отвори не прив'язані до конкретного гиба) — інші слаги → [].

Остання лінія оборони у воркері: навіть якщо API-gate обійдено, воркер
відмовляє ДО CAD-операції/запису у R2 з 422 RFC 9457.
"""

from __future__ import annotations

import math
from dataclasses import asdict, dataclass
from typing import Any

from flatcraft_cad.validate.bend import load_spec

# Допуск на представлення чисел із рухомою крапкою (CLAUDE.md §7 — межа «від
# краю», дзеркало TS `holes.ts::EDGE_DISTANCE_EPSILON_MM`). `edge_distance_mm`
# зазвичай похідне від `center_distance_mm - diameter_mm / 2`, і для чисел
# «рівно на межі» (напр. 9.7 - 3.2) IEEE-754 дає 6.499999999999999 замість
# 6.5 — без допуску гейт хибно блокує геометрично валідний отвір. 1e-9 на
# кілька порядків менший за будь-яку значущу відстань у мм, тож справжні
# порушення (напр. 9.69/Ø6.4) усе ще ловляться.
EDGE_DISTANCE_EPSILON_MM = 1e-9


@dataclass(frozen=True)
class HoleError:
    """Один елемент 422-detail. `code` збігається з кодом TS export-gate."""

    code: str
    field: str
    detail: str


def _fmt(n: float) -> str:
    return f"{round(n, 3):g}"


def validate_holes(
    template_slug: str,
    parameters: dict[str, Any],
    thickness_mm: float,
    material_code: str | None,
    spec: dict[str, Any] | None = None,
) -> list[HoleError]:
    """Перевіряє відстань отворів від лінії гиба. [] → валідно (разом з
    порожнім `holes` і шаблонами без цього поля).

    `material_code` обов'язковий (рішення Архітектора 2026-10-13, замінює
    2026-10-06): відсутній чи невідомий материал (немає у
    `hole_to_bend_distance.coefficient_by_material`, тобто і в переліку
    матеріалів) — коефіцієнт невідомий, перевірку зробити неможливо, і це
    САМЕ ПО СОБІ помилка (паритет з TS `holes.material_coefficient_missing` →
    `HOLE_MATERIAL_COEFFICIENT_MISSING`), а не мовчазний пропуск.

    Зіпсований отвір (немає `diameter_mm`/`distance_from_bend_mm`, не число,
    NaN/нескінченність) пропускається — скасовує перевірку ЛИШЕ себе, решта
    отворів перевіряється незалежно від порядку (issue #257 п.2).
    """
    if template_slug not in ("l_bracket", "z_bracket"):
        return []

    holes: list[dict[str, Any]] = parameters.get("holes") or []
    if not holes:
        return []

    try:
        spec = spec if spec is not None else load_spec()
        coeff = (
            None
            if material_code is None
            else spec["hole_to_bend_distance"]["coefficient_by_material"].get(material_code)
        )
        if coeff is None:
            return [
                HoleError(
                    code="HOLE_MATERIAL_COEFFICIENT_MISSING",
                    field="material_code",
                    detail=(
                        f"Для матеріалу {material_code} немає коефіцієнта відстані отвору від гиба."
                    ),
                )
            ]

        r = float(parameters["bend_radius_mm"])
        min_edge_mm = coeff * thickness_mm + r

        errors: list[HoleError] = []
        for idx, hole in enumerate(holes):
            try:
                diameter_mm = float(hole["diameter_mm"])
                center_distance_mm = float(hole["distance_from_bend_mm"])
            except (KeyError, TypeError, ValueError):
                # Зіпсований отвір (немає поля чи не число) — пропускаємо
                # ЛИШЕ його, решта отворів перевіряється незалежно від
                # порядку (issue #257 п.2).
                continue
            if not (math.isfinite(diameter_mm) and math.isfinite(center_distance_mm)):
                continue
            edge_distance_mm = center_distance_mm - diameter_mm / 2
            if edge_distance_mm < min_edge_mm - EDGE_DISTANCE_EPSILON_MM:
                min_center_mm = min_edge_mm + diameter_mm / 2
                errors.append(
                    HoleError(
                        code="HOLE_TOO_CLOSE_TO_BEND",
                        field=f"holes[{idx}].distance_from_bend_mm",
                        detail=(
                            f"Відсуньте отвір №{idx + 1} від лінії гиба: від краю отвору до "
                            f"гиба має бути не менше {_fmt(min_edge_mm)} мм, тобто від центру "
                            f"Ø{_fmt(diameter_mm)} — не менше {_fmt(min_center_mm)} мм "
                            f"(зараз {_fmt(center_distance_mm)} мм)."
                        ),
                    )
                )
        return errors
    except (KeyError, TypeError, ValueError):
        return []


def validate_export_holes(
    template_slug: str,
    parameters: dict[str, Any],
    thickness_mm: float,
    material_code: str | None = None,
) -> list[dict[str, str]]:
    """JSON-готовий список dict-ів для 422-detail (паритет з validate_export)."""
    return [
        asdict(e) for e in validate_holes(template_slug, parameters, thickness_mm, material_code)
    ]
