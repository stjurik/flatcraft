"""Z-кронштейн — параметрична модель.

Геометрія: 3 плоскі сегменти, з'єднані двома 90° гибами.

       ─────────────────────  ← top_flange (на висоті offset)
                            │
                            │  ← vertical middle (offset_mm)
                            │
                            ─────────────────────  ← bottom_flange (y=0)

3D-модель — union 3 box-ів (без точного fillet'у радіуса; точна
геометрія для лазера у DXF-розгортці). Bend radius впливає на unfold
формулу, не на 3D preview.

Контракт параметрів збігається з `packages/types/templates/z-bracket.ts`.
"""

from typing import Literal

import cadquery as cq
from pydantic import BaseModel, ConfigDict, Field, field_validator

from flatcraft_cad.templates.base import Template

ALLOWED_INNER_RADIUS_MM: tuple[float, ...] = (1.0, 2.5, 4.0, 5.0)


class ZBracketBuildParameters(BaseModel):
    """Усі параметри, потрібні CadQuery-builder'у."""

    model_config = ConfigDict(frozen=True, populate_by_name=True)

    top_flange_mm: float = Field(ge=20, le=500, description="Довжина верхньої полиці.")
    bottom_flange_mm: float = Field(ge=20, le=500, description="Довжина нижньої полиці.")
    offset_mm: float = Field(ge=20, le=500, description="Вертикальний offset = середня секція.")
    bend_radius_mm: float = Field(description="Внутрішній радіус гиба.")
    bend_angle_deg: Literal[90] = Field(default=90, description="MVP: тільки 90°.")
    width_mm: float = Field(ge=20, le=3000, description="Довжина гиба (extrude).")
    thickness_mm: float = Field(gt=0, le=10, description="Товщина листа.")

    @field_validator("bend_radius_mm")
    @classmethod
    def _radius_in_allowed_set(cls, value: float) -> float:
        if value not in ALLOWED_INNER_RADIUS_MM:
            raise ValueError(
                f"bend_radius_mm must be one of {list(ALLOWED_INNER_RADIUS_MM)}; got {value}"
            )
        return value


def build_z_bracket(params: ZBracketBuildParameters) -> cq.Workplane:
    """Збирає 3D Z-bracket: 3 plate-сегменти union'ані разом.

    Координати:
      X — уздовж довжини полиць
      Y — вертикальна вісь (висота profile)
      Z — ширина листа (width_mm)

    Bottom flange: X ∈ [0, bottom_flange], Y ∈ [0, t]
    Middle vertical: X ∈ [bottom_flange - t, bottom_flange], Y ∈ [0, offset + t]
    Top flange: X ∈ [bottom_flange - t, bottom_flange - t + top_flange], Y ∈ [offset, offset + t]
    """
    t = params.thickness_mm
    bf = params.bottom_flange_mm
    tf = params.top_flange_mm
    off = params.offset_mm
    w = params.width_mm

    bottom = cq.Workplane("XY").box(bf, t, w, centered=(False, False, False))
    middle = (
        cq.Workplane("XY")
        .workplane(offset=0)
        .box(t, off + t, w, centered=(False, False, False))
        .translate((bf - t, 0, 0))
    )
    top = (
        cq.Workplane("XY").box(tf, t, w, centered=(False, False, False)).translate((bf - t, off, 0))
    )
    return bottom.union(middle).union(top)


class ZBracketTemplate(Template[ZBracketBuildParameters]):
    """Адаптер для системи шаблонів. Slug збігається з seed."""

    name = "z_bracket"

    def build(self, params: ZBracketBuildParameters) -> cq.Workplane:
        return build_z_bracket(params)
