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
  Усі правила незалежні — порушені перевіряються разом, без раннього виходу.
  Правило пропускається лише тоді, коли відсутнє чи нечислове (None після
  `sanitize_for_gates`) саме поле, від якого воно залежить: 2a/2b від
  bend_radius_mm і товщини не залежать, 1/2c/2d — залежать.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any

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
    """`bool` — НЕ число тут (паритет з `validate/types.py::_parsed_float`:
    `sanitize_for_gates` уже нейтралізує нечислові значення до `None`, це —
    додатковий захист для прямих викликів повз гейт типів)."""
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    return None


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


def validate_enclosed_shelf(
    template_slug: str,
    parameters: dict[str, Any],
    thickness_mm: float,
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

    return errors


def validate_export_enclosed_shelf(
    template_slug: str,
    parameters: dict[str, Any],
    thickness_mm: float,
) -> list[dict[str, str]]:
    """JSON-готовий список dict-ів для 422-detail (паритет з validate_export)."""
    return [asdict(e) for e in validate_enclosed_shelf(template_slug, parameters, thickness_mm)]
