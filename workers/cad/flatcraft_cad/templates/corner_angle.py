"""Corner angle — підсилювальний кутник з авто-grid отворів.

Геометрія = L-кронштейн (2 полиці, 1 90° гиб), але hole pattern
автоматично генерується з параметрів rows×cols×margin.

Призначення: меблевий/конструкційний кутник, де користувач не задає
координат — лише кількість отворів у grid'і.

Контракт параметрів збігається з `packages/types/templates/corner-angle.ts`.
"""

from typing import Literal

import cadquery as cq
from pydantic import BaseModel, ConfigDict, Field, field_validator

from flatcraft_cad.templates.base import BendDirection, Template

ALLOWED_INNER_RADIUS_MM: tuple[float, ...] = (1.0, 2.5, 4.0, 5.0)


class CornerAngleBuildParameters(BaseModel):
    """Усі параметри corner_angle для CadQuery-builder'у.

    Holes генеруються автоматично з rows/cols/margin → `compute_corner_angle_holes`.
    Координати JSON-aliases збігаються з TS-схемою (snake_case).
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
    hole_diameter_mm: float = Field(ge=3, le=20, description="Діаметр отворів grid'у.")
    hole_rows: int = Field(ge=0, le=5, description="Рядів отворів вздовж ширини.")
    hole_cols: int = Field(ge=0, le=5, description="Колонок отворів вздовж полиці.")
    hole_margin_mm: float = Field(ge=5, le=50, description="Відступ від країв полиці.")

    @field_validator("bend_radius_mm")
    @classmethod
    def _radius_in_allowed_set(cls, value: float) -> float:
        if value not in ALLOWED_INNER_RADIUS_MM:
            raise ValueError(
                f"bend_radius_mm must be one of {list(ALLOWED_INNER_RADIUS_MM)}; got {value}"
            )
        return value


def build_corner_angle(params: CornerAngleBuildParameters) -> cq.Workplane:
    """3D corner_angle = L-profile, ідентичний L-кронштейну.

    Отвори не вирізаються у 3D-моделі (preview): для DXF/PDF вони
    обчислюються окремо через `compute_corner_angle_holes`. Це збігається
    зі стратегією L-bracket (web preview = solid extrude).
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
        .radiusArc((t, t + r), -r)
        .lineTo(t, a)
        .lineTo(0, a)
        .close()
    )
    return profile.extrude(w)


class CornerAngleTemplate(Template[CornerAngleBuildParameters]):
    """Адаптер шаблонів — slug збігається з seed.ts."""

    name = "corner_angle"

    def build(self, params: CornerAngleBuildParameters) -> cq.Workplane:
        return build_corner_angle(params)
