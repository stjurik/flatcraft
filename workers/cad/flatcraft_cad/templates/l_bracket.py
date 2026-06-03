"""L-кронштейн — параметрична модель.

Контракт параметрів збігається з `packages/types/src/templates/l-bracket.ts`
(Zod-схема у TS): web/api валідують одне й те саме, що ми тут.
TypeScript використовує camelCase (`legA_mm`); Pydantic — snake_case з
alias'ами, щоб JSON-обмін між сторонами лишався без перейменувань.

Додано `thickness_mm` — у TS-схемі його нема, бо там товщина — частина
`model_drafts.thickness_mm` (doc/05), а builder потребує її явно.

Геометрія:
- 2D L-профіль у площині XZ зі стінкою товщиною t, з'єднаний у внутрішньому
  куті дугою радіуса r (зовнішній радіус = r + t — без додаткового філлета,
  бо лист гнеться по нейтральній лінії).
- extrude по Y на width_mm → 3D кронштейн.

Видимі межі:
- xmax = leg_b_mm   (полиця B горизонтальна)
- zmax = leg_a_mm   (полиця A вертикальна)
- |y|   = width_mm  (екструзія)
"""

from typing import Literal

import cadquery as cq
from pydantic import BaseModel, ConfigDict, Field, field_validator

from flatcraft_cad.templates.base import BendDirection, Template

# Допустимі внутрішні радіуси з bend-machine spec (data/bend-machine-esi.yaml).
# Збігається з union у packages/types/src/templates/l-bracket.ts.
# Зберігається як `tuple[float, ...]` (а не Literal[1, 2.5, 4, 5]) бо
# mypy strict не дозволяє float у Literal — перевірка через field_validator.
ALLOWED_INNER_RADIUS_MM: tuple[float, ...] = (1.0, 2.5, 4.0, 5.0)


class LBracketBuildParameters(BaseModel):
    """Усі параметри, потрібні CadQuery-builder'у.

    Підмножина полів LBracketParameters у TS + `thickness_mm`.
    Валідація меж — Pydantic Field; cross-field перевірки (матеріал,
    радіус-vs-товщина) — у TS-валідаторах перед постановкою у чергу.

    JSON-aliases (legA_mm, legB_mm) — щоб приймати payload з web/api
    без conversion на стороні воркера.
    """

    model_config = ConfigDict(frozen=True, populate_by_name=True)

    leg_a_mm: float = Field(
        ge=20, le=500, alias="legA_mm", description="Висота вертикальної полиці."
    )
    leg_b_mm: float = Field(
        ge=20, le=500, alias="legB_mm", description="Глибина горизонтальної полиці."
    )
    bend_radius_mm: float = Field(description="Внутрішній радіус гиба.")
    bend_angle_deg: Literal[90] = Field(default=90, description="MVP: тільки 90°.")
    bend_direction: BendDirection = Field(
        default="down", description="Напрям згину (Hotfix 2.10.e)."
    )
    width_mm: float = Field(ge=20, le=3000, description="Довжина лінії гиба.")
    thickness_mm: float = Field(gt=0, le=10, description="Товщина листа.")

    @field_validator("bend_radius_mm")
    @classmethod
    def _radius_in_allowed_set(cls, value: float) -> float:
        if value not in ALLOWED_INNER_RADIUS_MM:
            raise ValueError(
                f"bend_radius_mm must be one of {list(ALLOWED_INNER_RADIUS_MM)}; got {value}"
            )
        return value


def build_l_bracket(params: LBracketBuildParameters) -> cq.Workplane:
    """Збирає 3D-модель L-кронштейна.

    Геометрія детермінована: однакові params → однакова `cq.Workplane`.
    Невалідні комбінації (наприклад t > r + дуже малий профіль) повинні
    відсіюватись валідатором у TS до виклику воркера.
    """
    a = params.leg_a_mm
    b = params.leg_b_mm
    t = params.thickness_mm
    r = params.bend_radius_mm
    w = params.width_mm

    profile = (
        cq.Workplane("XZ")
        .moveTo(0, 0)
        .lineTo(b, 0)
        .lineTo(b, t)
        .lineTo(t + r, t)
        # CW arc від точки (t+r, t) до (t, t+r) радіусом r (внутрішній кут).
        .radiusArc((t, t + r), -r)
        .lineTo(t, a)
        .lineTo(0, a)
        .close()
    )
    return profile.extrude(w)


class LBracketTemplate(Template[LBracketBuildParameters]):
    """Адаптер для системи шаблонів (worker/CLI). Slug збігається з
    `templates.slug` у БД (`packages/db/src/seed.ts` → "l_bracket")."""

    name = "l_bracket"

    def build(self, params: LBracketBuildParameters) -> cq.Workplane:
        return build_l_bracket(params)
