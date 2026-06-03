"""Wall shelf — U-channel настінна полиця.

Геометрія: back (стінка з mounting holes) → shelf (горизонтальна полиця) →
optional front lip (запобіжний край).

Координати profile у XY-площині (extrude по Z = width_mm):
- Back vertical: x ∈ [0, t], y ∈ [0, back_height]
- Shelf horizontal: x ∈ [0, shelf_depth], y ∈ [0, t]  (внизу back)
- Lip vertical: x ∈ [shelf_depth - t, shelf_depth], y ∈ [0, front_lip]

front_lip_mm = 0 → пропускаємо lip-сегмент (2 секції, 1 гиб).

Контракт параметрів збігається з `packages/types/src/templates/wall-shelf.ts`.
"""

from typing import Literal

import cadquery as cq
from pydantic import BaseModel, ConfigDict, Field, field_validator

from flatcraft_cad.templates.base import BendSpec, Template

ALLOWED_INNER_RADIUS_MM: tuple[float, ...] = (1.0, 2.5, 4.0, 5.0)


class WallShelfBuildParameters(BaseModel):
    """Параметри wall_shelf для CadQuery-builder'у.

    Mount holes авто-генеруються у unfold (як у corner_angle), а не вводяться
    координатно — користувач задає лише grid rows×cols.
    """

    model_config = ConfigDict(frozen=True, populate_by_name=True)

    back_height_mm: float = Field(ge=30, le=500, description="Висота back-стінки.")
    shelf_depth_mm: float = Field(ge=50, le=500, description="Глибина полиці.")
    front_lip_mm: float = Field(ge=0, le=100, description="Висота переднього лопику; 0 → no lip.")
    bend_radius_mm: float = Field(description="Внутрішній радіус гиба.")
    bend_angle_deg: Literal[90] = Field(default=90, description="MVP: тільки 90°.")
    bends: tuple[BendSpec, ...] = Field(
        default=(BendSpec(), BendSpec()),
        description="Напрям 1-2 гибів (Hotfix 2.10.e): [back→shelf, shelf→lip].",
    )
    width_mm: float = Field(ge=100, le=3000, description="Довжина полиці (= довжина гибу).")
    thickness_mm: float = Field(gt=0, le=10, description="Товщина листа.")
    mount_hole_diameter_mm: float = Field(ge=3, le=20, description="Діаметр mounting holes.")
    mount_hole_rows: int = Field(ge=0, le=5, description="Рядів отворів вздовж ширини.")
    mount_hole_cols: int = Field(ge=0, le=5, description="Колонок отворів уздовж back.")
    mount_hole_margin_mm: float = Field(ge=5, le=50, description="Відступ від країв back.")

    @field_validator("bend_radius_mm")
    @classmethod
    def _radius_in_allowed_set(cls, value: float) -> float:
        if value not in ALLOWED_INNER_RADIUS_MM:
            raise ValueError(
                f"bend_radius_mm must be one of {list(ALLOWED_INNER_RADIUS_MM)}; got {value}"
            )
        return value

    @field_validator("front_lip_mm")
    @classmethod
    def _lip_zero_or_min5(cls, value: float) -> float:
        # Або 0, або ≥5 — щоб уникнути занадто короткого 3-го сегменту.
        if value != 0.0 and value < 5.0:
            raise ValueError(f"front_lip_mm must be 0 or >= 5; got {value}")
        return value


def build_wall_shelf(params: WallShelfBuildParameters) -> cq.Workplane:
    """Збирає 3D wall_shelf union'ом 2 або 3 box'ів.

    Mount holes не вирізаються у 3D (лише у DXF), як і в інших шаблонах.
    """
    t = params.thickness_mm
    bh = params.back_height_mm
    sd = params.shelf_depth_mm
    lip = params.front_lip_mm
    w = params.width_mm

    back = cq.Workplane("XY").box(t, bh, w, centered=(False, False, False))
    shelf = cq.Workplane("XY").box(sd, t, w, centered=(False, False, False))
    result = back.union(shelf)

    if lip > 0:
        front = (
            cq.Workplane("XY")
            .box(t, lip, w, centered=(False, False, False))
            .translate((sd - t, 0, 0))
        )
        result = result.union(front)

    return result


class WallShelfTemplate(Template[WallShelfBuildParameters]):
    """Адаптер шаблонів — slug збігається з seed.ts."""

    name = "wall_shelf"

    def build(self, params: WallShelfBuildParameters) -> cq.Workplane:
        return build_wall_shelf(params)
