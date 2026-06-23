"""Perforated panel з КВАДРАТНИМИ отворами (Phase 3.0 PR 5, ADR-027 Рішення 6).

Окремий шаблон (НЕ extension `perforated_panel` через hole_shape) обрано для:
- regression isolation: existing perforated_panel snapshots байт-стабільні.
- per-template CAM-перевірка: LWPOLYLINE 4-vertex entities (square) можуть
  обробляти CAM-софт інакше за CIRCLE — окремий test cycle per template.

Геометрично: плоский box без гибів, grid центрованих квадратних отворів.
Layout identical до perforated_panel (одна centered grid), різниця тільки у
формі отворів — `Hole2D.shape='square'` замість 'circle'.

Параметр `hole_size_mm` — side length квадрата (eq. до hole_diameter_mm у круглого).
"""

import cadquery as cq
from pydantic import BaseModel, ConfigDict, Field

from flatcraft_cad.templates.base import Template


class PerforatedPanelSquareBuildParameters(BaseModel):
    """Параметри perforated_panel_square — grid square holes без bend-полів."""

    model_config = ConfigDict(frozen=True, populate_by_name=True)

    length_mm: float = Field(ge=100, le=3000, description="Довжина листа.")
    width_mm: float = Field(ge=100, le=3000, description="Ширина листа.")
    thickness_mm: float = Field(gt=0, le=10, description="Товщина листа.")
    hole_size_mm: float = Field(ge=3, le=30, description="Side length квадрата.")
    pitch_x_mm: float = Field(ge=10, le=200, description="Крок вздовж довжини.")
    pitch_y_mm: float = Field(ge=10, le=200, description="Крок вздовж ширини.")
    margin_mm: float = Field(ge=5, le=100, description="Мін. відступ від країв.")


def build_perforated_panel_square(
    params: PerforatedPanelSquareBuildParameters,
) -> cq.Workplane:
    """3D-модель: плоский box (як perforated_panel).

    Отвори не вирізаються у 3D (як і в усіх інших шаблонах) — лише у DXF.
    Square cuts емітяться `_export_flat_dxf` як LWPOLYLINE 4 vertices
    через Hole2D.shape='square'.
    """
    return cq.Workplane("XY").box(
        params.length_mm,
        params.thickness_mm,
        params.width_mm,
        centered=(False, False, False),
    )


class PerforatedPanelSquareTemplate(Template[PerforatedPanelSquareBuildParameters]):
    """Адаптер шаблонів — slug збігається з seed.ts (perforated_panel_square)."""

    name = "perforated_panel_square"

    def build(self, params: PerforatedPanelSquareBuildParameters) -> cq.Workplane:
        return build_perforated_panel_square(params)
