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

Доробка 049 (issue #274, рецензія Flash на PR #287): «число» тут — лише
СКІНЧЕННЕ число. `float("nan")`/`float("inf")`/`float("-inf")` не кидають
винятку (й Python JSON-парсер за замовчуванням так само пропускає літерали
`NaN`/`Infinity`/`-Infinity`), тож без `math.isfinite` нескінченне чи NaN
значення мовчки проходило б цей гейт як число — і падало б у гейти нижче
(`validate/sheet.py` зокрема) без захисту. Також перевіряється ФОРМА
контейнерів: `holes` має бути списком об'єктів (не рядком/числом/об'єктом;
елемент — об'єктом, не чимось іншим), `side_perforation`/`stiffening_rib` —
об'єктом або `null`. Без цього `holes: "not-a-list"`/`holes: [123]` мовчки
ковталися б (holes.py ітерує й пропускає зіпсоване — тихо, без 422).
"""

from __future__ import annotations

import math
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


def _parsed_float(value: Any) -> float | None:
    """`None` — значення взагалі не число (навіть як рядок). `bool` — НЕ
    число тут, хоч Python/Pydantic і трактують його як int/float
    (контрприклади Argon: `true` у `pitch_x_mm`/`bend_angle_deg` не має
    мовчки ставати 1.0). Рядок-число ("5", "15", навіть "-2.5") — число,
    `float()` розбирає і його."""
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return None
    return None


def _is_number(value: Any) -> bool:
    """Доробка 049 (issue #274, рецензія Flash): `float()` розбирає і
    "nan"/"inf"/"-inf" (будь-яким регістром), а JSON-парсер Python за
    замовчуванням пропускає літерали `NaN`/`Infinity`/`-Infinity` без
    помилки — тож без `math.isfinite` нескінченне чи NaN значення мовчки
    проходило б як «число»."""
    parsed = _parsed_float(value)
    return parsed is not None and math.isfinite(parsed)


def _type_label(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "логічне значення (true/false)"
    if isinstance(value, list):
        return "список"
    if isinstance(value, dict):
        return "об'єкт"
    parsed = _parsed_float(value)
    if parsed is not None and not math.isfinite(parsed):
        return "нескінченне або NaN значення"
    if isinstance(value, str):
        return "рядок, який не є числом"
    return type(value).__name__


def _shape_label(value: Any) -> str:
    """Для помилок форми контейнера (`holes`/`side_perforation`/
    `stiffening_rib`) — на відміну від `_type_label`, тут не йдеться про
    «число», тож рядок/число підписуються без згадки про число."""
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "логічне значення (true/false)"
    if isinstance(value, list):
        return "список"
    if isinstance(value, dict):
        return "об'єкт"
    if isinstance(value, str):
        return "рядок"
    if isinstance(value, (int, float)):
        return "число"
    return type(value).__name__


def _field_error(value: Any, field: str) -> ParameterTypeError | None:
    if _is_number(value):
        return None
    return ParameterTypeError(
        code=TYPE_ERROR_CODE,
        field=field,
        detail=f"Параметр «{field}» має бути числом, отримано: {_type_label(value)}.",
    )


def _container_error(field: str, value: Any, expected: str) -> ParameterTypeError:
    return ParameterTypeError(
        code=TYPE_ERROR_CODE,
        field=field,
        detail=f"Параметр «{field}» має бути {expected}, отримано: {_shape_label(value)}.",
    )


def validate_types(template_slug: str, parameters: dict[str, Any]) -> list[ParameterTypeError]:
    """Перевіряє типи числових полів (верхній рівень + holes[]/side_perforation/
    stiffening_rib) і форму контейнерів (`holes` — список об'єктів,
    `side_perforation`/`stiffening_rib` — об'єкт). Порожній список → усі
    присутні числові поля — числа, усі присутні контейнери — правильної форми.

    Перевіряється лише те, що ПРИСУТНЄ у `parameters` (`field in parameters`,
    не `.get`): відсутнє поле — питання Pydantic-дефолту чи обов'язковості,
    не типу, і цей гейт у нього не лізе. Присутнє явне `null` — для числового
    поля це помилка типу (воно в переліку BAD, не «поле не задано»); для
    контейнера `null` — як і раніше, валідне «немає» (паритет з `None`-дефолтом
    `side_perforation`/`stiffening_rib` у моделі enclosed_shelf).
    """
    errors: list[ParameterTypeError] = []

    for field in TOP_LEVEL_NUMERIC_FIELDS.get(template_slug, ()):
        if field in parameters:
            err = _field_error(parameters[field], field)
            if err is not None:
                errors.append(err)

    hole_fields = HOLE_LIST_NUMERIC_FIELDS.get(template_slug)
    if hole_fields and "holes" in parameters:
        holes = parameters["holes"]
        if holes is not None:
            if not isinstance(holes, list):
                errors.append(_container_error("holes", holes, "списком"))
            else:
                for idx, hole in enumerate(holes):
                    if not isinstance(hole, dict):
                        errors.append(_container_error(f"holes.{idx}", hole, "об'єктом"))
                        continue
                    for field in hole_fields:
                        if field in hole:
                            err = _field_error(hole[field], f"holes.{idx}.{field}")
                            if err is not None:
                                errors.append(err)

    for obj_name, obj_fields in NESTED_OBJECT_NUMERIC_FIELDS.get(template_slug, {}).items():
        if obj_name in parameters:
            obj = parameters[obj_name]
            if obj is not None:
                if not isinstance(obj, dict):
                    errors.append(_container_error(obj_name, obj, "об'єктом"))
                else:
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
    """Нейтралізує значення полів, що провалили перевірку типу чи форми,
    замінюючи їх на `None` у НОВОМУ dict (оригінал не мутується).

    ВЕРХНІЙ РІВЕНЬ (поле без крапки, напр. `bend_radius_mm`, `holes`,
    `stiffening_rib`): решта гейтів (`validate/bend.py`,
    `validate/perforation.py`) читає ці поля через `parameters.get(...)` і
    трактує `None` як «поле відсутнє» — рано повертає `[]` замість падіння на
    `float("not-a-number")`/`float([1, 2])` (там немає try/except, на відміну
    від profile.py/sheet.py, де пряме читання вже обгорнуте).

    ВКЛАДЕНІ поля об'єктів (`side_perforation.*`, `stiffening_rib.*`) теж
    нейтралізуються — доробка 049 (issue #274, рецензія Flash): `float("inf")`
    не кидає винятку, тож `stiffening_rib.height_mm: "inf"` без нейтралізації
    доходило до `validate/sheet.py::_sheet_dimensions_mm` (`float()` без
    `isfinite`) і давало побічний `SHEET_EXCEEDS_MAX_LENGTH` з «inf мм» поряд
    з `INVALID_PARAMETER_TYPE`. Елементи `holes[]` з помилкою форми
    (`holes.<idx>` — елемент не об'єкт) тут НЕ чіпаються: `validate/holes.py`
    вже безпечно пропускає нечисловий/не-dict елемент (TypeError на
    `hole["diameter_mm"]` ловиться власним try/except модуля), а поля
    `holes[].*` (`holes.<idx>.<field>`) теж не нейтралізуються — там же
    `math.isfinite`-перевірка вже стоїть ПЕРЕД порівнянням.
    """
    bad_top_level_fields = {e["field"] for e in type_errors if "." not in e["field"]}
    bad_nested_fields: dict[str, set[str]] = {}
    for error in type_errors:
        head, sep, tail = error["field"].partition(".")
        if sep and head != "holes":
            bad_nested_fields.setdefault(head, set()).add(tail)

    if not bad_top_level_fields and not bad_nested_fields:
        return parameters

    sanitized = {
        key: (None if key in bad_top_level_fields else value) for key, value in parameters.items()
    }
    for obj_name, bad_leaf_fields in bad_nested_fields.items():
        obj = sanitized.get(obj_name)
        if isinstance(obj, dict):
            sanitized[obj_name] = {
                leaf: (None if leaf in bad_leaf_fields else value) for leaf, value in obj.items()
            }
    return sanitized
