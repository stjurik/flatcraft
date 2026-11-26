"""Parity sheet-size валідатор (CLAUDE.md §7 п.4).

Дзеркало TS `packages/cad-engine/src/validators/export-gate.ts`
(`sheetDimensionsFor` + `validateExportSheet`). Та сама формула розгортки, що
й `unfold.py` — bend allowance через ОДНУ спільну `compute_bend_allowance`
(не дублюється по кожному шаблону, як і в unfold.py), не грубе «сума полиць
без BA».

Остання лінія оборони у воркері: навіть якщо API-gate обійдено, воркер
відмовляє ДО CAD-операції/запису у R2 з 422 RFC 9457.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any

from flatcraft_cad.bend_allowance import compute_bend_allowance
from flatcraft_cad.k_factor import compute_k_factor
from flatcraft_cad.validate.bend import load_spec


@dataclass(frozen=True)
class SheetError:
    """Один елемент 422-detail. `code` збігається з кодом TS export-gate."""

    code: str
    field: str
    detail: str


def _fmt(n: float) -> str:
    return f"{round(n, 3):g}"


def _enclosed_shelf_dimensions_mm(
    parameters: dict[str, Any], t: float, r: float, ba: float
) -> tuple[float, float]:
    """Х/Y bbox за формулами `unfold_enclosed_shelf` (паритет — не грубе
    «back визначає все»): left/right звисають за межі bottom/back навіть БЕЗ
    ребра (на (t+r)/2 — `left_y_offset = (flat_bottom_y - depth_mm)/2`), тож
    min/max беремо по всіх сегментах (bottom, back, left/right, опц. rib), а
    не лише по back+bottom."""
    tr = t + r
    width_mm = float(parameters["width_mm"])
    depth_mm = float(parameters["depth_mm"])
    rib: dict[str, Any] | None = parameters.get("stiffening_rib")

    flat_left_right = depth_mm - tr
    width = width_mm - 2 * tr + 2 * ba + 2 * flat_left_right

    flat_bottom_y = depth_mm - tr - (tr if rib is not None else 0.0)
    flat_back_y = depth_mm - tr
    left_y_offset = (flat_bottom_y - depth_mm) / 2.0

    top_candidates = [flat_bottom_y, flat_bottom_y + ba + flat_back_y, left_y_offset + depth_mm]
    bottom_candidates = [0.0, left_y_offset]
    if rib is not None:
        flat_rib_y = float(rib["height_mm"]) - tr
        bottom_candidates.append(-ba - flat_rib_y)

    height = max(top_candidates) - min(bottom_candidates)
    return width, height


def _sheet_dimensions_mm(
    template_slug: str,
    parameters: dict[str, Any],
    thickness_mm: float,
    material_code: str,
    spec: dict[str, Any] | None = None,
) -> tuple[float, float] | None:
    """Дзеркало TS `sheetDimensionsFor`. `None` — радіус/кут невідомі, шаблон
    без bend-полів чи параметри неповні (KeyError/TypeError/ValueError —
    пряме читання `parameters[...]`, Zod/Pydantic-схема звітує про причину
    пізніше): `validate_export` (bend) чи схема шаблону вже звітує про реальну
    причину. Невідомий матеріал (`compute_k_factor` кидає ValueError) теж
    потрапляє у цей except — `validate_export`/`validate_holes` уже звітують
    MATERIAL_NOT_ALLOWED/HOLE_MATERIAL_COEFFICIENT_MISSING."""
    t = thickness_mm
    try:
        r = float(parameters["bend_radius_mm"])
        angle = float(parameters["bend_angle_deg"])

        k_factor = compute_k_factor(material_code, t, r, spec)
        ba = compute_bend_allowance(
            angle_deg=angle, inner_radius_mm=r, thickness_mm=t, k_factor=k_factor
        )

        if template_slug in ("l_bracket", "corner_angle"):
            flat_a = parameters["legA_mm"] - t - r
            flat_b = parameters["legB_mm"] - t - r
            return float(parameters["width_mm"]), flat_b + ba + flat_a

        if template_slug == "z_bracket":
            flat_bottom = parameters["bottom_flange_mm"] - t - r
            flat_middle = parameters["offset_mm"] - t - r
            flat_top = parameters["top_flange_mm"] - t - r
            return float(parameters["width_mm"]), flat_bottom + ba + flat_middle + ba + flat_top

        if template_slug == "wall_shelf":
            lip_present = parameters["front_lip_mm"] > 0
            flat_back = parameters["back_height_mm"] - t - r
            flat_shelf = parameters["shelf_depth_mm"] - (t + r) - ((t + r) if lip_present else 0.0)
            if lip_present:
                flat_lip = parameters["front_lip_mm"] - t - r
                height = flat_back + ba + flat_shelf + ba + flat_lip
            else:
                height = flat_back + ba + flat_shelf
            return float(parameters["width_mm"]), height

        if template_slug == "perforated_panel":
            flange = parameters["rib_height_mm"] - (t + r)
            width = parameters["length_mm"] + 2 * (ba + flange)
            height = parameters["width_mm"] + 2 * (ba + flange)
            return width, height

        if template_slug == "enclosed_shelf":
            return _enclosed_shelf_dimensions_mm(parameters, t, r, ba)

        return None
    except (KeyError, TypeError, ValueError):
        return None


def _try_float(value: Any) -> float | None:
    """`None` — значення відсутнє чи не конвертується (контракт як
    `profile.py::_try_float`): безпечний `float()` для вже type-gated/
    sanitize_for_gates-очищених `parameters`."""
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _common_bend_allowance(
    parameters: dict[str, Any], thickness_mm: float, material_code: str, spec: dict[str, Any]
) -> tuple[float, float] | tuple[None, None]:
    """(радіус, bend allowance) — спільна залежність обох осей розгортки.
    `(None, None)` — радіус/кут відсутні чи нечислові, або K-фактор не
    рахується (невідомий матеріал/ratio поза діапазоном): інший гейт
    (`validate_export`/`validate_export` bend) уже звітує реальну причину."""
    try:
        r = float(parameters["bend_radius_mm"])
        angle = float(parameters["bend_angle_deg"])
        k_factor = compute_k_factor(material_code, thickness_mm, r, spec)
        ba = compute_bend_allowance(
            angle_deg=angle, inner_radius_mm=r, thickness_mm=thickness_mm, k_factor=k_factor
        )
        return r, ba
    except (KeyError, TypeError, ValueError):
        return None, None


def _enclosed_shelf_axis_dimensions_mm(
    parameters: dict[str, Any], t: float, r: float, ba: float
) -> tuple[float | None, float | None]:
    """Дзеркало `_enclosed_shelf_dimensions_mm`, але ширина і висота —
    НЕЗАЛЕЖНІ (issue #296): ширина взагалі не читає `stiffening_rib`, а
    висота лишається `None`, якщо ребро присутнє, але його `height_mm`
    зіпсоване (значення потрібне для формули — вигадувати його небезпечно,
    тож ця вісь просто пропускається, а не рахується з дефолтом)."""
    tr = t + r
    width_mm = _try_float(parameters.get("width_mm"))
    depth_mm = _try_float(parameters.get("depth_mm"))
    rib_raw = parameters.get("stiffening_rib")
    rib: dict[str, Any] | None = rib_raw if isinstance(rib_raw, dict) else None
    rib_present = rib is not None

    width = None
    if width_mm is not None and depth_mm is not None:
        flat_left_right = depth_mm - tr
        width = width_mm - 2 * tr + 2 * ba + 2 * flat_left_right

    height = None
    if depth_mm is not None:
        rib_height = _try_float(rib.get("height_mm")) if rib is not None else None
        if not rib_present or rib_height is not None:
            flat_bottom_y = depth_mm - tr - (tr if rib_present else 0.0)
            flat_back_y = depth_mm - tr
            left_y_offset = (flat_bottom_y - depth_mm) / 2.0
            top_candidates = [
                flat_bottom_y,
                flat_bottom_y + ba + flat_back_y,
                left_y_offset + depth_mm,
            ]
            bottom_candidates = [0.0, left_y_offset]
            if rib_present and rib_height is not None:
                bottom_candidates.append(-ba - (rib_height - tr))
            height = max(top_candidates) - min(bottom_candidates)
    return width, height


def _axis_dimensions_mm(
    template_slug: str, parameters: dict[str, Any], t: float, r: float, ba: float
) -> tuple[float | None, float | None]:
    """(ширина, довжина-вздовж-профілю) розгортки — КОЖНА вісь незалежна
    (issue #296): корумповане/відсутнє поле, від якого залежить лише ОДНА
    вісь, не ховає перевірку іншої (на відміну від `_sheet_dimensions_mm`,
    де одна спільна `try/except` на всю деталь губила обидві відразу, щойно
    перше ж поле не конвертувалось у `float`). Спільні `r`/`ba` вже
    обчислені (`_common_bend_allowance`) — якщо вони не рахуються, обидві
    осі однаково невідомі (викликається лише тоді, коли обчислились)."""

    def f(key: str) -> float | None:
        return _try_float(parameters.get(key))

    if template_slug in ("l_bracket", "corner_angle"):
        width = f("width_mm")
        leg_a = f("legA_mm")
        leg_b = f("legB_mm")
        height = (
            (leg_b - t - r) + ba + (leg_a - t - r)
            if leg_a is not None and leg_b is not None
            else None
        )
        return width, height

    if template_slug == "z_bracket":
        width = f("width_mm")
        bottom = f("bottom_flange_mm")
        middle = f("offset_mm")
        top = f("top_flange_mm")
        height = None
        if bottom is not None and middle is not None and top is not None:
            height = (bottom - t - r) + ba + (middle - t - r) + ba + (top - t - r)
        return width, height

    if template_slug == "wall_shelf":
        width = f("width_mm")
        back = f("back_height_mm")
        shelf = f("shelf_depth_mm")
        lip = f("front_lip_mm")
        height = None
        if back is not None and shelf is not None and lip is not None:
            lip_present = lip > 0
            flat_back = back - t - r
            flat_shelf = shelf - (t + r) - ((t + r) if lip_present else 0.0)
            height = (
                flat_back + ba + flat_shelf + ba + (lip - t - r)
                if lip_present
                else flat_back + ba + flat_shelf
            )
        return width, height

    if template_slug == "perforated_panel":
        length = f("length_mm")
        width_p = f("width_mm")
        rib = f("rib_height_mm")
        flange = rib - (t + r) if rib is not None else None
        width = length + 2 * (ba + flange) if length is not None and flange is not None else None
        height = width_p + 2 * (ba + flange) if width_p is not None and flange is not None else None
        return width, height

    if template_slug == "enclosed_shelf":
        return _enclosed_shelf_axis_dimensions_mm(parameters, t, r, ba)

    return None, None


def validate_sheet(
    template_slug: str,
    parameters: dict[str, Any],
    thickness_mm: float,
    material_code: str,
    spec: dict[str, Any] | None = None,
) -> list[SheetError]:
    """Габарит розгортки vs можливості верстата (CLAUDE.md §7 п.4). [] → валідно.

    K-фактор рахується за матеріалом (`compute_k_factor`, ADR-043) — та сама
    функція, якою `server.py` будує реальну розгортку, тож гейт і воркер
    завжди бачать той самий габарит.

    Issue #296: ширина і довжина вздовж профілю перевіряються НЕЗАЛЕЖНО
    (`_axis_dimensions_mm`) — зіпсоване поле, від якого залежить лише одна
    вісь, не ховає перевищення по іншій.
    """
    spec = spec if spec is not None else load_spec()
    t = thickness_mm
    r, ba = _common_bend_allowance(parameters, t, material_code, spec)
    if r is None or ba is None:
        return []
    row = next((r2 for r2 in spec["capability_matrix"] if r2["thickness_mm"] == thickness_mm), None)
    if row is None:
        return []  # validate_export (bend) вже звітує THICKNESS_NOT_SUPPORTED

    width, height = _axis_dimensions_mm(template_slug, parameters, t, r, ba)
    known_dims = [d for d in (width, height) if d is not None]
    if not known_dims or max(known_dims) <= row["max_bend_length_mm"]:
        return []
    max_dim = max(known_dims)
    return [
        SheetError(
            code="SHEET_EXCEEDS_MAX_LENGTH",
            field="width_mm",
            detail=(
                f"Зменшіть габарити деталі: розгорнута заготовка ({_fmt(max_dim)} мм) "
                "перевищує максимальну довжину гиба верстата для цієї товщини."
            ),
        )
    ]


def validate_export_sheet(
    template_slug: str,
    parameters: dict[str, Any],
    thickness_mm: float,
    material_code: str,
) -> list[dict[str, str]]:
    """JSON-готовий список dict-ів для 422-detail (паритет з validate_export)."""
    return [
        asdict(e) for e in validate_sheet(template_slug, parameters, thickness_mm, material_code)
    ]
