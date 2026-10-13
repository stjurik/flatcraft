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
from flatcraft_cad.validate.bend import load_spec


@dataclass(frozen=True)
class SheetError:
    """Один елемент 422-detail. `code` збігається з кодом TS export-gate."""

    code: str
    field: str
    detail: str


def _fmt(n: float) -> str:
    return f"{round(n, 3):g}"


def _compute_k_factor(
    material_code: str,
    thickness_mm: float,
    inner_radius_mm: float,
    spec: dict[str, Any],
) -> float | None:
    """Дзеркало TS `computeKFactor` (k-factor.ts). `None` — невідомий матеріал
    чи ratio поза будь-яким `ratio_correction` діапазоном."""
    base = spec["k_factor"]["default_by_material"].get(material_code)
    if base is None or thickness_mm <= 0:
        return None
    ratio = inner_radius_mm / thickness_mm
    for row in spec["k_factor"]["ratio_correction"]:
        if row["ratio_min"] <= ratio < row["ratio_max"]:
            return float(base) * float(row["multiplier"])
    return None


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
    material_code: str | None,
    spec: dict[str, Any],
) -> tuple[float, float] | None:
    """Дзеркало TS `sheetDimensionsFor`. `None` — матеріал/радіус/кут невідомі,
    шаблон без bend-полів чи параметри неповні (KeyError/TypeError/ValueError —
    пряме читання `parameters[...]`, Zod/Pydantic-схема звітує про причину
    пізніше): `validate_export` (bend) чи схема шаблону вже звітує про реальну
    причину."""
    if material_code is None:
        return None
    t = thickness_mm
    try:
        r = float(parameters["bend_radius_mm"])
        angle = float(parameters["bend_angle_deg"])

        k = _compute_k_factor(material_code, t, r, spec)
        if k is None:
            return None
        ba = compute_bend_allowance(angle_deg=angle, inner_radius_mm=r, thickness_mm=t, k_factor=k)

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


def validate_sheet(
    template_slug: str,
    parameters: dict[str, Any],
    thickness_mm: float,
    material_code: str | None,
    spec: dict[str, Any] | None = None,
) -> list[SheetError]:
    """Габарит розгортки vs можливості верстата (CLAUDE.md §7 п.4). [] → валідно."""
    spec = spec if spec is not None else load_spec()
    dims = _sheet_dimensions_mm(template_slug, parameters, thickness_mm, material_code, spec)
    if dims is None:
        return []
    row = next((r for r in spec["capability_matrix"] if r["thickness_mm"] == thickness_mm), None)
    if row is None:
        return []  # validate_export (bend) вже звітує THICKNESS_NOT_SUPPORTED

    max_dim = max(dims)
    if max_dim <= row["max_bend_length_mm"]:
        return []
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
    material_code: str | None = None,
) -> list[dict[str, str]]:
    """JSON-готовий список dict-ів для 422-detail (паритет з validate_export)."""
    return [
        asdict(e) for e in validate_sheet(template_slug, parameters, thickness_mm, material_code)
    ]
