"""Отвір l_bracket/z_bracket — обов'язкові ключі й межі (issue #289).

Дзеркало Zod `HoleSchema` у `packages/types/src/templates/l-bracket.ts` і
`z-bracket.ts` (ADR-019 parity): `leg`/`segment`-enum, `.min()`/`.max()` на
числових полях отвору, `.max(20)` на масиві `holes`. Воркер — остання лінія
оборони: прямий `POST /export` обходить Fastify/Zod-гейт API, а Pydantic-моделі
`LBracketBuildParameters`/`ZBracketBuildParameters` поля `holes` не мають
(зайве ігнорується) — без цього гейта `holes: [{}]` чи отвір з від'ємним
діаметром проходив як 200.

Працює на СИРИХ `parameters` (до `_params_with_defaults` у `server.py`):
відсутність ключа в отворі — властивість запиту клієнта, а не питання
Pydantic-дефолту. `type_errors` (гейт 049, `validate/types.py`) — щоб не
дублювати помилку: поле з уже виставленим `INVALID_PARAMETER_TYPE` (нечислове,
NaN/inf) не отримує ще й «бракує»/«поза межами» тут.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any

from flatcraft_cad.validate.types import _parsed_float

MAX_HOLES = 20

# `leg`/`segment` — назва й дозволені значення поля-дискримінатора секції
# (паритет з `z.enum([...])` у відповідній Zod-схемі).
_CHOICE_FIELD: dict[str, str] = {"l_bracket": "leg", "z_bracket": "segment"}
_CHOICE_VALUES: dict[str, tuple[str, ...]] = {
    "l_bracket": ("A", "B"),
    "z_bracket": ("T", "M", "B"),
}

# (поле, мін, макс-або-None) — паритет з `z.number().min()/.max()` обох схем.
_RANGE_FIELDS: tuple[tuple[str, float, float | None], ...] = (
    ("distance_from_edge_mm", 5, None),
    ("distance_from_bend_mm", 5, None),
    ("diameter_mm", 2, 50),
)
_REQUIRED_NUMERIC_FIELDS = tuple(field for field, _, _ in _RANGE_FIELDS)


@dataclass(frozen=True)
class HoleShapeError:
    """Один елемент 422-detail."""

    code: str
    field: str
    detail: str


def _fmt(n: float) -> str:
    return f"{round(n, 3):g}"


def _range_detail(idx: int, field: str, value: float, lo: float, hi: float | None) -> str:
    bound = f"від {_fmt(lo)} мм" if hi is None else f"від {_fmt(lo)} до {_fmt(hi)} мм"
    return f"Отвір №{idx + 1}: «{field}» = {_fmt(value)} мм поза межами ({bound})."


def validate_hole_shape(
    template_slug: str,
    raw_parameters: dict[str, Any],
    type_errors: list[dict[str, str]],
) -> list[HoleShapeError]:
    """Перевіряє обов'язкові ключі й межі отворів `l_bracket`/`z_bracket`.
    [] → валідно (разом з іншими шаблонами й порожнім/відсутнім `holes`).

    `holes` не списком чи елемент не об'єктом — поза цим гейтом: це вже
    помилка гейта типів (049, `validate/types.py`), тут такий отвір/контейнер
    просто пропускається, без дублю.
    """
    choice_field = _CHOICE_FIELD.get(template_slug)
    if choice_field is None:
        return []

    holes = raw_parameters.get("holes")
    if not isinstance(holes, list):
        return []

    errors: list[HoleShapeError] = []
    if len(holes) > MAX_HOLES:
        errors.append(
            HoleShapeError(
                code="HOLE_TOO_MANY",
                field="holes",
                detail=f"Забагато отворів: {len(holes)}, максимум {MAX_HOLES}.",
            )
        )

    type_error_fields = {e["field"] for e in type_errors if e["code"] == "INVALID_PARAMETER_TYPE"}
    choice_values = _CHOICE_VALUES[template_slug]

    for idx, hole in enumerate(holes):
        if not isinstance(hole, dict):
            continue
        if f"holes.{idx}" in type_error_fields:
            continue

        for key in (choice_field, *_REQUIRED_NUMERIC_FIELDS):
            if key not in hole:
                errors.append(
                    HoleShapeError(
                        code="HOLE_FIELD_MISSING",
                        field=f"holes.{idx}.{key}",
                        detail=f"Отвір №{idx + 1}: відсутнє обов'язкове поле «{key}».",
                    )
                )

        if choice_field in hole:
            # `in` на кортежі рядків, не на множині: нехешоване значення
            # (список/словник) не повинно давати 500 (КП-2/3).
            choice_value = hole[choice_field]
            if choice_value not in choice_values:
                errors.append(
                    HoleShapeError(
                        code="HOLE_INVALID_CHOICE",
                        field=f"holes.{idx}.{choice_field}",
                        detail=(
                            f"Отвір №{idx + 1}: недозволене значення «{choice_field}»; "
                            f"дозволені: {', '.join(choice_values)}."
                        ),
                    )
                )

        for field, lo, hi in _RANGE_FIELDS:
            if field not in hole:
                continue
            field_path = f"holes.{idx}.{field}"
            if field_path in type_error_fields:
                continue
            value = _parsed_float(hole[field])
            if value is None:
                continue
            if value < lo or (hi is not None and value > hi):
                errors.append(
                    HoleShapeError(
                        code="HOLE_VALUE_OUT_OF_RANGE",
                        field=field_path,
                        detail=_range_detail(idx, field, value, lo, hi),
                    )
                )

    return errors


def validate_export_hole_shape(
    template_slug: str,
    raw_parameters: dict[str, Any],
    type_errors: list[dict[str, str]],
) -> list[dict[str, str]]:
    """JSON-готовий список dict-ів для 422-detail (паритет з validate_export)."""
    return [asdict(e) for e in validate_hole_shape(template_slug, raw_parameters, type_errors)]
