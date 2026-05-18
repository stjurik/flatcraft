"""Perforated panel — плоский лист з grid отворів.

Принципово: НЕ має гибів. Геометрія = box(length × thickness × width),
отвори вирізаються у DXF як CIRCLE на INNER_CUTS layer.

Grid auto-центрується:
- n_cols = floor((length - 2*margin) / pitch_x) + 1
- effective_margin_x = (length - (n_cols - 1) * pitch_x) / 2
Аналогічно для рядів. Так grid симетричний відносно центра панелі.

Контракт параметрів збігається з `packages/types/templates/perforated-panel.ts`.
"""

import cadquery as cq
from pydantic import BaseModel, ConfigDict, Field

from flatcraft_cad.templates.base import Template


class PerforatedPanelBuildParameters(BaseModel):
    """Параметри perforated_panel — лише грид-розміри (без bend-полів)."""

    model_config = ConfigDict(frozen=True, populate_by_name=True)

    length_mm: float = Field(ge=100, le=3000, description="Довжина листа.")
    width_mm: float = Field(ge=100, le=3000, description="Ширина листа.")
    thickness_mm: float = Field(gt=0, le=10, description="Товщина листа.")
    hole_diameter_mm: float = Field(ge=3, le=30, description="Діаметр отворів.")
    pitch_x_mm: float = Field(ge=10, le=200, description="Крок вздовж довжини.")
    pitch_y_mm: float = Field(ge=10, le=200, description="Крок вздовж ширини.")
    margin_mm: float = Field(ge=5, le=100, description="Мін. відступ від країв.")


def build_perforated_panel(params: PerforatedPanelBuildParameters) -> cq.Workplane:
    """3D-модель: плоский box.

    Отвори не вирізаються у 3D (як і в інших шаблонах) — лише у DXF.
    """
    return cq.Workplane("XY").box(
        params.length_mm,
        params.thickness_mm,
        params.width_mm,
        centered=(False, False, False),
    )


class PerforatedPanelTemplate(Template[PerforatedPanelBuildParameters]):
    """Адаптер шаблонів — slug збігається з seed.ts."""

    name = "perforated_panel"

    def build(self, params: PerforatedPanelBuildParameters) -> cq.Workplane:
        return build_perforated_panel(params)
