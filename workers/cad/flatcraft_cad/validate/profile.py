"""Parity profile-валідатор (Hotfix 2.9.f, ADR-026).

Дзеркало TS `packages/cad-engine/src/validators/profile.ts` — геометрична
достатність профілю (плече/полиця/offset відносно товщина+радіус). Той самий
набір правил, що й assertion'и `packages/ui/src/3d-viewport/geometry.ts`.

Остання лінія оборони у воркері: навіть якщо API-gate (Fastify) обійдено, воркер
відмовляє ДО CAD-операції/запису у R2 із 422 RFC 9457.

Strictness ТОЧНО як у geometry.ts / TS-валідаторі:
  - legs (l_bracket/corner_angle): валідно при leg >= t+r  (assert `t+r > leg`)
  - z/wall flanges, offset, shelf: валідно при value > threshold (assert `value <= ...`)
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any

_LABEL = {
    "legA": "Довжина плеча A",
    "legB": "Довжина плеча B",
    "top_flange": "Верхня полиця",
    "bottom_flange": "Нижня полиця",
    "offset": "Вертикальний offset",
    "back_height": "Висота задньої стінки",
    "shelf_depth": "Глибина полиці",
}


@dataclass(frozen=True)
class ProfileError:
    """Один елемент 422-detail. `code` збігається з кодами TS-валідатора."""

    code: str
    field: str
    detail: str


def _fmt(n: float) -> str:
    return f"{round(n, 3):g}"


def _min_msg(which: str, minimum: float, t: float, r: float) -> str:
    return (
        f"Збільшіть «{_LABEL.get(which, which)}» до мінімум {_fmt(minimum)} мм "
        f"(товщина {_fmt(t)} + радіус {_fmt(r)})."
    )


def _gt_msg(which: str, threshold: float, t: float, r: float) -> str:
    return (
        f"Збільшіть «{_LABEL.get(which, which)}»: потрібно більше за {_fmt(threshold)} мм "
        f"(товщина {_fmt(t)} + радіус {_fmt(r)})."
    )


def validate_profile(
    template_slug: str,
    parameters: dict[str, Any],
    thickness_mm: float,
) -> list[ProfileError]:
    """Перевіряє геометричну достатність профілю. Порожній список → валідно.

    perforated_panel (без гибу) та невідомий slug → []. thickness <= 0 → []
    (як `t <= 0` early-return у geometry.ts; Pydantic відмовить окремо).
    """
    t = thickness_mm
    if t <= 0:
        return []

    errors: list[ProfileError] = []

    def leg(which: str, value: float, r: float) -> None:
        # geometry.ts: `t + r > leg` → invalid. Валідно при leg >= t+r.
        if t + r > value:
            errors.append(
                ProfileError(code="LEG_TOO_SHORT", field=which, detail=_min_msg(which, t + r, t, r))
            )

    def flange(which: str, value: float, r: float) -> None:
        # geometry.ts: `flange <= t+r` → invalid. Валідно при flange > t+r.
        if value <= t + r:
            errors.append(
                ProfileError(
                    code="FLANGE_TOO_SHORT", field=which, detail=_gt_msg(which, t + r, t, r)
                )
            )

    if template_slug in ("l_bracket", "corner_angle"):
        r = float(parameters["bend_radius_mm"])
        leg("legA", float(parameters["legA_mm"]), r)
        leg("legB", float(parameters["legB_mm"]), r)
        return errors

    if template_slug == "z_bracket":
        r = float(parameters["bend_radius_mm"])
        off = float(parameters["offset_mm"])
        if off <= r:
            errors.append(
                ProfileError(
                    code="OFFSET_TOO_SMALL", field="offset", detail=_gt_msg("offset", r, t, r)
                )
            )
        flange("top_flange", float(parameters["top_flange_mm"]), r)
        flange("bottom_flange", float(parameters["bottom_flange_mm"]), r)
        return errors

    if template_slug == "wall_shelf":
        r = float(parameters["bend_radius_mm"])
        flange("back_height", float(parameters["back_height_mm"]), r)
        lip = float(parameters.get("front_lip_mm", 0))
        sd = float(parameters["shelf_depth_mm"])
        threshold = 2 * (t + r) if lip > 0 else (t + r)
        if sd <= threshold:
            errors.append(
                ProfileError(
                    code="SHELF_TOO_SHORT",
                    field="shelf_depth",
                    detail=_gt_msg("shelf_depth", threshold, t, r),
                )
            )
        return errors

    return errors


def validate_export_profile(
    template_slug: str,
    parameters: dict[str, Any],
    thickness_mm: float,
) -> list[dict[str, str]]:
    """JSON-готовий список dict-ів для 422-detail (паритет з validate_export)."""
    return [asdict(e) for e in validate_profile(template_slug, parameters, thickness_mm)]
