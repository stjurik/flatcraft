"""Enclosed shelf — настінна полиця з 4-сторонньою cross-розгорткою.

Phase 3.0 PR 7b (ADR-027). Pydantic-параметри (7a) + 3D builder (7b).
Unfold/DXF — у unfold.py і export/dxf.py відповідно. Server handler (`/export`
routing) + PDF + R3F + web studio — PR 7c.

Геометрія (див. enclosed-shelf.ts для діаграми):
- bottom: width_mm × depth_mm (центральна площина).
- back: width_mm × depth_mm (вертикальна стінка, UP-bend).
- left/right: depth_mm × depth_mm (квадратні бокові, UP-bend по Y-осі).
- front rib (опц.): width_mm × stiffening_rib.height_mm (UP-bend).

`depth_mm` — спільний параметр для висоти back AND розмірів бокових стінок
(інваріант ADR-027 Рішення 5).
"""

from typing import Literal

import cadquery as cq
from pydantic import BaseModel, ConfigDict, Field, field_validator

from flatcraft_cad.templates.base import BendSpec, Template

ALLOWED_INNER_RADIUS_MM: tuple[float, ...] = (1.0, 2.5, 4.0, 5.0)


class EnclosedShelfSidePerforation(BaseModel):
    """Опційна декоративна перфорація бокових стінок (квадратні отвори)."""

    model_config = ConfigDict(frozen=True, populate_by_name=True)

    hole_size_mm: float = Field(ge=3, le=20, description="Сторона квадратного отвору.")
    pitch_x_mm: float = Field(ge=10, le=100, description="Pitch між отворами по X.")
    pitch_y_mm: float = Field(ge=10, le=100, description="Pitch між отворами по Y.")
    margin_mm: float = Field(ge=5, le=50, description="Відступ від країв бокової стінки.")


class EnclosedShelfStiffeningRib(BaseModel):
    """Опційне ребро жорсткості — front lip bottom (UP-bend)."""

    model_config = ConfigDict(frozen=True, populate_by_name=True)

    height_mm: float = Field(ge=5, le=50, description="Висота ребра після гибу.")


class EnclosedShelfBuildParameters(BaseModel):
    """Параметри enclosed_shelf для CadQuery-builder'у (паритет з TS-схемою).

    `bends`: tuple з 3 або 4 BendSpec залежно від наявності stiffening_rib.
    Дефолт усіх — 'up' (enclosed-форма, на відміну від wall_shelf 'down').
    """

    model_config = ConfigDict(frozen=True, populate_by_name=True)

    width_mm: float = Field(ge=300, le=1000, description="Довжина полиці (= ширина bottom).")
    depth_mm: float = Field(
        ge=100,
        le=300,
        description="Глибина полиці (= висота back AND сторона квадратних боковин).",
    )
    bend_radius_mm: float = Field(description="Внутрішній радіус гиба.")
    bend_angle_deg: Literal[90] = Field(default=90, description="MVP: тільки 90°.")
    bends: tuple[BendSpec, ...] = Field(
        default=(BendSpec(direction="up"),) * 4,
        description="Напрям 3-4 гибів: [back, left, right, rib?].",
    )
    thickness_mm: float = Field(gt=0, le=10, description="Товщина листа.")
    side_perforation: EnclosedShelfSidePerforation | None = Field(
        default=None, description="Опційна перфорація боковин."
    )
    stiffening_rib: EnclosedShelfStiffeningRib | None = Field(
        default=None, description="Опційне 5-те ребро жорсткості (front-lip bottom)."
    )

    @field_validator("bend_radius_mm")
    @classmethod
    def _radius_in_allowed_set(cls, value: float) -> float:
        if value not in ALLOWED_INNER_RADIUS_MM:
            raise ValueError(
                f"bend_radius_mm must be one of {list(ALLOWED_INNER_RADIUS_MM)}; got {value}"
            )
        return value

    @field_validator("bends")
    @classmethod
    def _bends_count_3_or_4(cls, value: tuple[BendSpec, ...]) -> tuple[BendSpec, ...]:
        if len(value) not in (3, 4):
            raise ValueError(f"bends must contain 3 or 4 items; got {len(value)}")
        return value


def build_enclosed_shelf(params: EnclosedShelfBuildParameters) -> cq.Workplane:
    """Збирає 3D enclosed_shelf union'ом 4-5 box'ів (Z — vertical).

    Конвенція осей:
    - X: ширина полиці (left → right), x ∈ [0, width_mm].
    - Y: глибина полиці (front → back), y ∈ [0, depth_mm].
    - Z: vertical, +Z вгору.

    Сегменти:
    - bottom: x∈[0,w], y∈[0,d], z∈[0,t]. Лежить плашмя.
    - back: x∈[0,w], y∈[d-t,d], z∈[t,t+d]. Вертикальна стінка ззаду.
    - left: x∈[0,t], y∈[0,d], z∈[t,t+d]. Вертикальна стінка зліва.
    - right: x∈[w-t,w], y∈[0,d], z∈[t,t+d]. Вертикальна стінка справа.
    - rib (опц.): x∈[0,w], y∈[0,t], z∈[t,t+rh]. Front-edge ребро жорсткості.

    Side perforation НЕ вирізається у 3D — лише у DXF (як і в інших шаблонах).
    """
    t = params.thickness_mm
    w = params.width_mm
    d = params.depth_mm

    bottom = cq.Workplane("XY").box(w, d, t, centered=(False, False, False))
    back = cq.Workplane("XY").box(w, t, d, centered=(False, False, False)).translate((0, d - t, t))
    left = cq.Workplane("XY").box(t, d, d, centered=(False, False, False)).translate((0, 0, t))
    right = cq.Workplane("XY").box(t, d, d, centered=(False, False, False)).translate((w - t, 0, t))

    result = bottom.union(back).union(left).union(right)

    if params.stiffening_rib is not None:
        rh = params.stiffening_rib.height_mm
        rib = cq.Workplane("XY").box(w, t, rh, centered=(False, False, False)).translate((0, 0, t))
        result = result.union(rib)

    return result


class EnclosedShelfTemplate(Template[EnclosedShelfBuildParameters]):
    """Адаптер шаблону — slug збігається з seed.ts."""

    name = "enclosed_shelf"

    def build(self, params: EnclosedShelfBuildParameters) -> cq.Workplane:
        return build_enclosed_shelf(params)
