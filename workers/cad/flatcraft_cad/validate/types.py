"""Type-гейт (issue #274): числовий параметр не того типу → 422, не 500/200.

Остання лінія оборони у воркері (ADR-019) — навіть якщо API-gate (Zod)
обійдено, пряме звернення до `/export` з рядком/списком/`null`/`bool`/
словником у числовому полі має давати 422 зі списком помилок, а не 500
(`float()`/порівняння падає у `validate/bend.py`,`perforation.py`) і не
мовчазний 200 (holes.py й sheet.py вже самі ковтають погані типи —
`validate_holes`/`_sheet_dimensions_mm` — і просто не перевіряють те, чого
не можуть прочитати).

Працює НАД сирими `parameters` із payload, ДО `_params_with_defaults`
(`server.py`): Pydantic за замовчуванням лояльно приводить `bool` до
`1.0`/`0.0` і рядок-число до `float` (лояльний режим, перевірено напряму) —
тож перевірка типу вже ПІСЛЯ злиття з Pydantic-дефолтами пропустила б
`bend_radius_mm: true`, якщо випадковий результат коерсії (`1.0`) проходить
і діапазон, і кастомний валідатор моделі. Рядок-число ("5", "15") — єдиний
виняток: це валідне число (паритет з Pydantic-коерсією і тестами #257
TestStringNumberInParameters), решта гейтів бачить його приведеним.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any

# Числові поля верхнього рівня (JSON/alias-імена — ті самі, що читають
# validate/bend.py, sheet.py, profile.py, perforation.py), по slug'у.
TOP_LEVEL_NUMERIC_FIELDS: dict[str, tuple[str, ...]] = {
    "l_bracket": ("legA_mm", "legB_mm", "bend_radius_mm", "bend_angle_deg", "width_mm"),
    "z_bracket": (
        "top_flange_mm",
        "bottom_flange_mm",
        "offset_mm",
        "bend_radius_mm",
        "bend_angle_deg",
        "width_mm",
    ),
    "corner_angle": (
        "legA_mm",
        "legB_mm",
        "bend_radius_mm",
        "bend_angle_deg",
        "width_mm",
        "hole_diameter_mm",
        "hole_rows",
        "hole_cols",
        "hole_margin_mm",
    ),
    "wall_shelf": (
        "back_height_mm",
        "shelf_depth_mm",
        "front_lip_mm",
        "bend_radius_mm",
        "bend_angle_deg",
        "width_mm",
        "mount_hole_diameter_mm",
        "mount_hole_rows",
        "mount_hole_cols",
        "mount_hole_margin_mm",
    ),
    "perforated_panel": (
        "length_mm",
        "width_mm",
        "hole_size_mm",
        "pitch_x_mm",
        "pitch_y_mm",
        "margin_mm",
        "rib_height_mm",
        "rib_corner_radius_mm",
        "corner_hole_inset_mm",
        "bend_radius_mm",
        "bend_angle_deg",
    ),
    "enclosed_shelf": ("width_mm", "depth_mm", "bend_radius_mm", "bend_angle_deg"),
}

# Отвори-списком (`parameters["holes"]`) — лише l_bracket/z_bracket
# (corner_angle/wall_shelf — auto-grid, perforated_panel/enclosed_shelf — не
# прив'язані до конкретного гиба; паритет з validate/holes.py).
HOLE_LIST_NUMERIC_FIELDS: dict[str, tuple[str, ...]] = {
    "l_bracket": ("distance_from_edge_mm", "distance_from_bend_mm", "diameter_mm"),
    "z_bracket": ("distance_from_edge_mm", "distance_from_bend_mm", "diameter_mm"),
}

# Вкладені опційні об'єкти (enclosed_shelf) — паритет з
# `EnclosedShelfSidePerforation`/`EnclosedShelfStiffeningRib`.
NESTED_OBJECT_NUMERIC_FIELDS: dict[str, dict[str, tuple[str, ...]]] = {
    "enclosed_shelf": {
        "side_perforation": ("hole_size_mm", "pitch_x_mm", "pitch_y_mm", "margin_mm"),
        "stiffening_rib": ("height_mm",),
    },
}

TYPE_ERROR_CODE = "INVALID_PARAMETER_TYPE"


@dataclass(frozen=True)
class ParameterTypeError:
    """Один елемент 422-detail. `code` == `TYPE_ERROR_CODE` для всіх помилок цього гейта."""

    code: str
    field: str
    detail: str


def _is_number(value: Any) -> bool:
    """`bool` — НЕ число тут, хоч Python/Pydantic і трактують його як int/float
    (контрприклади Argon: `true` у `pitch_x_mm`/`bend_angle_deg` не має
    мовчки ставати 1.0). Рядок-число ("5", "15", навіть "-2.5") — число."""
    if isinstance(value, bool):
        return False
    if isinstance(value, (int, float)):
        return True
    if isinstance(value, str):
        try:
            float(value)
        except ValueError:
            return False
        return True
    return False


def _type_label(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "логічне значення (true/false)"
    if isinstance(value, list):
        return "список"
    if isinstance(value, dict):
        return "об'єкт"
    if isinstance(value, str):
        return "рядок, який не є числом"
    return type(value).__name__


def _field_error(value: Any, field: str) -> ParameterTypeError | None:
    if _is_number(value):
        return None
    return ParameterTypeError(
        code=TYPE_ERROR_CODE,
        field=field,
        detail=f"Параметр «{field}» має бути числом, отримано: {_type_label(value)}.",
    )


def validate_types(template_slug: str, parameters: dict[str, Any]) -> list[ParameterTypeError]:
    """Перевіряє типи числових полів (верхній рівень + holes[]/side_perforation/
    stiffening_rib). Порожній список → усі присутні числові поля — числа.

    Перевіряється лише те, що ПРИСУТНЄ у `parameters` (`field in parameters`,
    не `.get`): відсутнє поле — питання Pydantic-дефолту чи обов'язковості,
    не типу, і цей гейт у нього не лізе. Присутнє явне `null` — так, помилка
    типу (воно в переліку BAD, не «поле не задано»).
    """
    errors: list[ParameterTypeError] = []

    for field in TOP_LEVEL_NUMERIC_FIELDS.get(template_slug, ()):
        if field in parameters:
            err = _field_error(parameters[field], field)
            if err is not None:
                errors.append(err)

    hole_fields = HOLE_LIST_NUMERIC_FIELDS.get(template_slug)
    holes = parameters.get("holes")
    if hole_fields and isinstance(holes, list):
        for idx, hole in enumerate(holes):
            if not isinstance(hole, dict):
                continue
            for field in hole_fields:
                if field in hole:
                    err = _field_error(hole[field], f"holes.{idx}.{field}")
                    if err is not None:
                        errors.append(err)

    for obj_name, obj_fields in NESTED_OBJECT_NUMERIC_FIELDS.get(template_slug, {}).items():
        obj = parameters.get(obj_name)
        if isinstance(obj, dict):
            for field in obj_fields:
                if field in obj:
                    err = _field_error(obj[field], f"{obj_name}.{field}")
                    if err is not None:
                        errors.append(err)

    return errors


def validate_export_types(template_slug: str, parameters: dict[str, Any]) -> list[dict[str, str]]:
    """JSON-готовий список dict-ів для 422-detail (паритет з validate_export)."""
    return [asdict(e) for e in validate_types(template_slug, parameters)]


def sanitize_for_gates(
    parameters: dict[str, Any], type_errors: list[dict[str, str]]
) -> dict[str, Any]:
    """Нейтралізує значення полів ВЕРХНЬОГО РІВНЯ, що провалили перевірку
    типу, замінюючи їх на `None` у НОВОМУ dict (оригінал не мутується).

    Решта гейтів (`validate/bend.py`, `validate/perforation.py`) читає ці
    поля через `parameters.get(...)` і трактує `None` як «поле відсутнє» —
    рано повертає `[]` замість падіння на `float("not-a-number")`/
    `float([1, 2])` (там немає try/except, на відміну від profile.py/sheet.py,
    де пряме читання вже обгорнуте). Вкладені поля (`holes[].*`,
    `side_perforation.*`, `stiffening_rib.*`) тут не чіпаються — гейти, що їх
    читають, уже безпечно пропускають зіпсовані значення (bool-перевірка й
    try/except у `validate/holes.py`, зовнішній try/except у
    `validate/sheet.py::_sheet_dimensions_mm`).
    """
    bad_top_level_fields = {e["field"] for e in type_errors if "." not in e["field"]}
    if not bad_top_level_fields:
        return parameters
    return {
        key: (None if key in bad_top_level_fields else value) for key, value in parameters.items()
    }
