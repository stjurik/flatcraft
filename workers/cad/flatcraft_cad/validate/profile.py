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
    "rib_height": "Висота ребра",
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


def _try_float(value: Any) -> float | None:
    """`None` — значення відсутнє чи не конвертується (контракт як
    `parameters.get(key)` з наступним безпечним `float()`). Рядок-число
    ("80") — число, `float()` розбирає і його (паритет з Pydantic-коерсією)."""
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def validate_profile(
    template_slug: str,
    parameters: dict[str, Any],
    thickness_mm: float,
) -> list[ProfileError]:
    """Перевіряє геометричну достатність профілю. Порожній список → валідно.

    Невідомий slug → []. thickness <= 0 → [] (як `t <= 0` early-return у
    geometry.ts; Pydantic відмовить окремо).

    Issue #296: кожна перевірка (кожна полиця/ребро/offset/shelf_depth)
    незалежна — відсутнє чи нечислове (`None` після `sanitize_for_gates`)
    значення скасовує ЛИШЕ ту перевірку, що від нього залежить, а не всі
    перевірки шаблону (раніше одна спільна `try/except` на весь шаблон
    губила решту помилок, щойно перше ж поле не конвертувалось у `float`).
    Дефолти гейта (`bend_radius_mm` 2.5, `front_lip_mm` 0) — лише для
    ВІДСУТНЬОГО ключа (`dict.get(key, default)` вже й так повертає `None`,
    а не дефолт, коли ключ присутній зі зіпсованим значенням).
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
        r = _try_float(parameters.get("bend_radius_mm"))
        if r is None:
            return errors
        leg_a = _try_float(parameters.get("legA_mm"))
        if leg_a is not None:
            leg("legA", leg_a, r)
        leg_b = _try_float(parameters.get("legB_mm"))
        if leg_b is not None:
            leg("legB", leg_b, r)
        return errors

    if template_slug == "z_bracket":
        r = _try_float(parameters.get("bend_radius_mm"))
        if r is None:
            return errors
        off = _try_float(parameters.get("offset_mm"))
        if off is not None and off <= r:
            errors.append(
                ProfileError(
                    code="OFFSET_TOO_SMALL", field="offset", detail=_gt_msg("offset", r, t, r)
                )
            )
        top = _try_float(parameters.get("top_flange_mm"))
        if top is not None:
            flange("top_flange", top, r)
        bottom = _try_float(parameters.get("bottom_flange_mm"))
        if bottom is not None:
            flange("bottom_flange", bottom, r)
        return errors

    if template_slug == "perforated_panel":
        # Ребриста монтажна панель (ADR-030/031): flat-фланець = rib_height − (t+r)
        # має бути додатним → rib_height > t+r (як flange у z/wall).
        r = _try_float(parameters.get("bend_radius_mm", 2.5))
        if r is None:
            return errors
        rib = _try_float(parameters.get("rib_height_mm"))
        if rib is not None:
            flange("rib_height", rib, r)
        return errors

    if template_slug == "wall_shelf":
        r = _try_float(parameters.get("bend_radius_mm"))
        if r is None:
            return errors
        back = _try_float(parameters.get("back_height_mm"))
        if back is not None:
            flange("back_height", back, r)
        lip = _try_float(parameters.get("front_lip_mm", 0))
        sd = _try_float(parameters.get("shelf_depth_mm"))
        if sd is not None and lip is not None:
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
