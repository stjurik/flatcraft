"""Parity-валідатор enclosed_shelf (issue #283): ребро жорсткості і перфорація
боковин. Дзеркало TS `packages/cad-engine/src/validators/enclosed-shelf.ts`.

Остання лінія оборони у воркері (ADR-019) — навіть якщо Fastify-gate
обійдено, воркер відмовляє ДО CAD-операції/запису у R2 з 422 RFC 9457, а не
мовчить (DXF без отворів боковин, `unfold.py::_enclosed_shelf_side_holes` →
`avail_x < 0` → `()`) чи падає 500 (`unfold_enclosed_shelf` кидає `ValueError`
на замале ребро поза `try` у `server.py`).

Правила (позначення: t=thickness_mm, r=bend_radius_mm, d=depth_mm):
  1. stiffening_rib.height_mm > t + r (строго) — інакше FLANGE_TOO_SHORT
     (той самий код, що rib_height у perforated_panel, `validate/profile.py`).
  2. side_perforation (h=hole_size_mm, m=margin_mm, w = d − (t+r) — вужча вісь
     боковини, та сама формула, що `avail_x` у `_enclosed_shelf_side_holes`):
     a. pitch_x_mm > h, pitch_y_mm > h — інакше HOLES_OVERLAP (окремо на кожну вісь).
     b. m > h/2 — інакше MARGIN_TOO_SMALL (отвір виходить на край стінки).
     c. 2·m ≤ w — інакше PERFORATION_DOES_NOT_FIT на margin_mm (не вміщається).
     d. h < w — інакше PERFORATION_DOES_NOT_FIT на hole_size_mm (отвір більший
        за боковину) — окрема підказка («зменшіть отвір»), щоб не ходити по
        колу з (c) («зменшіть відступ»).
     e. (issue #303) ефективний відступ сітки отворів по осі X (лінія гиба
        боковина↔дно) мінус h/2 ≥ a·t+r (a — коефіцієнт
        `hole_to_bend_distance.coefficient_by_material[material_code]`,
        CLAUDE.md §7) — інакше HOLE_TOO_CLOSE_TO_BEND на margin_mm. Рахується
        лише коли отвори реально є (інакше про них нічого сказати — вже
        ловить (c)); невідомий material_code — правило пропускається
        (матеріал ловить власний гейт).
     f. (issue #303) ефективний відступ сітки по осі Y мінус h/2 ≥ q — інакше
        HOLE_IN_CORNER_TAB на margin_mm, де q = tr, якщо задано ребро
        жорсткості, інакше tr/2 (висота смуги кутового виступу боковини —
        похідна від `flat_bottom_y` у `unfold.py::unfold_enclosed_shelf`, не
        залежить від depth_mm). Не залежить від матеріалу.
  Усі правила незалежні — порушені перевіряються разом, без раннього виходу.
  Правило пропускається лише тоді, коли відсутнє чи нечислове (None після
  `sanitize_for_gates`) саме поле, від якого воно залежить: 2a/2b від
  bend_radius_mm і товщини не залежать, 1/2c/2d/2e/2f — залежать (2f — від
  материалу не залежить, 2e — залежить).
"""

from __future__ import annotations

import math
from dataclasses import asdict, dataclass
from typing import Any

from flatcraft_cad.validate.bend import load_spec

from .types import _parsed_float

# Допуск на представлення чисел із рухомою крапкою (CLAUDE.md §7 — межа «від
# краю»), той самий 1e-9, що `validate/holes.py::EDGE_DISTANCE_EPSILON_MM` і
# TS `holes.ts`/`enclosed-shelf.ts`.
EDGE_DISTANCE_EPSILON_MM = 1e-9

_AXIS_LABEL = {
    "pitch_x_mm": "Крок X",
    "pitch_y_mm": "Крок Y",
}


@dataclass(frozen=True)
class EnclosedShelfError:
    """Один елемент 422-detail. `code` збігається з кодом TS-валідатора."""

    code: str
    field: str
    detail: str


def _fmt(n: float) -> str:
    return f"{round(n, 3):g}"


def _as_float(value: Any) -> float | None:
    """Число для правил гейта або `None`. Той самий контракт, що й
    `validate/types.py::_parsed_float`: `bool` — не число, рядок-число ("10") —
    число. Рядок лишається рядком, якщо Pydantic у `_params_with_defaults`
    (server.py) провалилась з іншої причини — як у `perforation.py` (#274);
    без цього гейт сліпнув на всіх правилах (контрприклад Argon, PR #314).
    Не скінченне — `None`: його ловить гейт типів."""
    f = _parsed_float(value)
    return f if f is not None and math.isfinite(f) else None


def _rib_msg(h: float, tr: float, t: float, r: float) -> str:
    return (
        f"Збільшіть «Висота ребра»: потрібно більше за {_fmt(tr)} мм "
        f"(товщина {_fmt(t)} + радіус {_fmt(r)}) — зараз {_fmt(h)} мм."
    )


def _overlap_msg(axis: str, pitch: float, hole: float) -> str:
    return (
        f"Збільшіть «{_AXIS_LABEL.get(axis, axis)}»: крок {_fmt(pitch)} мм має бути "
        f"більший за сторону отвору {_fmt(hole)} мм — інакше сусідні отвори перетинаються."
    )


def _margin_too_small_msg(margin: float, hole: float) -> str:
    return (
        f"Збільшіть «Відступ від країв»: відступ {_fmt(margin)} мм має бути більший за "
        f"половину сторони отвору ({_fmt(hole / 2)} мм) — інакше отвір виходить на край стінки."
    )


def _fit_margin_msg(margin: float, depth: float, w: float) -> str:
    return (
        f"Зменшіть «Відступ від країв» ({_fmt(margin)} мм): при глибині {_fmt(depth)} мм "
        f"боковина вміщає перфорацію шириною {_fmt(w)} мм, а подвоєний відступ "
        f"{_fmt(2 * margin)} мм перевищує її."
    )


def _fit_hole_msg(hole: float, w: float) -> str:
    return (
        f"Зменшіть «Сторона □»: отвір {_fmt(hole)} мм не вміщається у боковину "
        f"шириною {_fmt(w)} мм."
    )


def _too_close_to_bend_msg(edge_x: float, min_hb: float, coeff: float, t: float, r: float) -> str:
    return (
        f"Збільшіть «Відступ від країв» чи «Крок X», або зменшіть отвір: відстань від краю "
        f"найближчого отвору до лінії гиба боковина↔дно {_fmt(edge_x)} мм менша за мінімум "
        f"{_fmt(min_hb)} мм (a·t+R = {_fmt(coeff)}×{_fmt(t)}+{_fmt(r)})."
    )


def _corner_tab_msg(edge_y: float, q: float) -> str:
    return (
        f"Перемістіть ряд отворів усередину чи зменшіть отвір: ряд заходить у кутовий виступ "
        f"боковини на {_fmt(q - edge_y)} мм (відступ від виступу {_fmt(edge_y)} мм, потрібно "
        f"не менше {_fmt(q)} мм)."
    )


def _side_perforation_effective_margins(
    w: float, h: float, pitch_x: float, pitch_y: float, margin: float
) -> tuple[float, float] | None:
    """Ефективні відступи центрованої сітки отворів (issue #303) — та сама
    формула, що `unfold.py::_enclosed_shelf_side_holes`. `None`, якщо отворів
    взагалі немає (`avail < 0` по будь-якій осі, уже ловить (c))."""
    avail_x = w - 2 * margin
    avail_y = h - 2 * margin
    if avail_x < 0 or avail_y < 0:
        return None
    # Крок ≤ 0 (зіпсований запит повз Pydantic) — розкладки немає; без цього
    # `avail // 0` дав би ZeroDivisionError → 500 (контрприклад Argon, рецензія #321).
    # HOLES_OVERLAP на такий крок уже видає правило (a).
    if pitch_x <= 0 or pitch_y <= 0:
        return None
    n_cols = int(avail_x // pitch_x) + 1
    n_rows = int(avail_y // pitch_y) + 1
    eff_margin_x = (w - (n_cols - 1) * pitch_x) / 2.0
    eff_margin_y = (h - (n_rows - 1) * pitch_y) / 2.0
    return eff_margin_x, eff_margin_y


def validate_enclosed_shelf(
    template_slug: str,
    parameters: dict[str, Any],
    thickness_mm: float,
    material_code: str | None = None,
) -> list[EnclosedShelfError]:
    """Перевіряє ребро жорсткості і перфорацію боковин. Порожній список — валідно.

    Невідомий slug → []. Неповні/нечислові `parameters` (KeyError/TypeError з
    прямого читання) не падають — кожне правило пропускається незалежно, за
    власним набором полів, від яких воно залежить.
    """
    if template_slug != "enclosed_shelf":
        return []

    errors: list[EnclosedShelfError] = []
    t = _as_float(thickness_mm)
    r = _as_float(parameters.get("bend_radius_mm"))
    depth = _as_float(parameters.get("depth_mm"))

    rib = parameters.get("stiffening_rib")
    if isinstance(rib, dict):
        h_rib = _as_float(rib.get("height_mm"))
        if h_rib is not None and t is not None and r is not None:
            tr = t + r
            if h_rib <= tr:
                errors.append(
                    EnclosedShelfError(
                        code="FLANGE_TOO_SHORT",
                        field="stiffening_rib.height_mm",
                        detail=_rib_msg(h_rib, tr, t, r),
                    )
                )

    side = parameters.get("side_perforation")
    if isinstance(side, dict):
        hole = _as_float(side.get("hole_size_mm"))
        margin = _as_float(side.get("margin_mm"))
        pitch_x = _as_float(side.get("pitch_x_mm"))
        pitch_y = _as_float(side.get("pitch_y_mm"))

        # 2c від отвору не залежить: зіпсований hole_size_mm не ховає її (рецензія #314,
        # паритет із TS, де правила йдуть підряд).
        if margin is not None and t is not None and r is not None and depth is not None:
            w = depth - (t + r)
            if 2 * margin > w:
                errors.append(
                    EnclosedShelfError(
                        code="PERFORATION_DOES_NOT_FIT",
                        field="side_perforation.margin_mm",
                        detail=_fit_margin_msg(margin, depth, w),
                    )
                )

        if hole is not None:
            for axis, pitch in (("pitch_x_mm", pitch_x), ("pitch_y_mm", pitch_y)):
                if pitch is not None and pitch <= hole:
                    errors.append(
                        EnclosedShelfError(
                            code="HOLES_OVERLAP",
                            field=f"side_perforation.{axis}",
                            detail=_overlap_msg(axis, pitch, hole),
                        )
                    )

            if margin is not None and margin <= hole / 2:
                errors.append(
                    EnclosedShelfError(
                        code="MARGIN_TOO_SMALL",
                        field="side_perforation.margin_mm",
                        detail=_margin_too_small_msg(margin, hole),
                    )
                )

            if t is not None and r is not None and depth is not None:
                w = depth - (t + r)
                if hole >= w:
                    errors.append(
                        EnclosedShelfError(
                            code="PERFORATION_DOES_NOT_FIT",
                            field="side_perforation.hole_size_mm",
                            detail=_fit_hole_msg(hole, w),
                        )
                    )

                if pitch_x is not None and pitch_y is not None and margin is not None:
                    grid = _side_perforation_effective_margins(w, depth, pitch_x, pitch_y, margin)
                    if grid is not None:
                        eff_margin_x, eff_margin_y = grid
                        tr = t + r
                        rib_present = isinstance(rib, dict)

                        coeff = (
                            None
                            if material_code is None
                            else load_spec()["hole_to_bend_distance"][
                                "coefficient_by_material"
                            ].get(material_code)
                        )
                        if coeff is not None:
                            min_hb = coeff * t + r
                            edge_x = eff_margin_x - hole / 2
                            if edge_x < min_hb - EDGE_DISTANCE_EPSILON_MM:
                                errors.append(
                                    EnclosedShelfError(
                                        code="HOLE_TOO_CLOSE_TO_BEND",
                                        field="side_perforation.margin_mm",
                                        detail=_too_close_to_bend_msg(edge_x, min_hb, coeff, t, r),
                                    )
                                )

                        q = tr if rib_present else tr / 2
                        edge_y = eff_margin_y - hole / 2
                        if edge_y < q - EDGE_DISTANCE_EPSILON_MM:
                            errors.append(
                                EnclosedShelfError(
                                    code="HOLE_IN_CORNER_TAB",
                                    field="side_perforation.margin_mm",
                                    detail=_corner_tab_msg(edge_y, q),
                                )
                            )

    return errors


def validate_export_enclosed_shelf(
    template_slug: str,
    parameters: dict[str, Any],
    thickness_mm: float,
    material_code: str | None = None,
) -> list[dict[str, str]]:
    """JSON-готовий список dict-ів для 422-detail (паритет з validate_export)."""
    return [
        asdict(e)
        for e in validate_enclosed_shelf(template_slug, parameters, thickness_mm, material_code)
    ]
