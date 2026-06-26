"""Перфорована МОНТАЖНА панель — ОДИН параметричний шаблон (ADR-031).

Раніше було два окремих шаблони: `perforated_panel` (круглий плаский лист) і
`perforated_panel_square` (квадратний ребристий лоток, ADR-030) з клієнтським
toggle-shim (ADR-029). ADR-031 уніфікує їх у ОДИН ребристий лоток, де форма
перфо-отвору — звичайний параметр `hole_shape` (circle|square). Круглий і
квадратний варіанти ідентичні в усьому, крім геометрії отвору.

Геометрія (розгортка — хрест/плюс, деталі у unfold.py):
- центральна перфо-площина length×width (між лініями гибу);
- 4 фланці, гнуті 90° назад (DOWN — вниз у 3D), висота `rib_height_mm`, однакова;
- вільні кути фланців скруглені R=`rib_corner_radius_mm` (дефолт 5);
- кутова розрядка автоматична (відкриті кути — фланці не накладаються при гибі);
- 4 установочні отвори Ø5.5 на площині, inset `corner_hole_inset_mm` від кутів.

Параметр `hole_size_mm` — діаметр (circle) або side length (square) перфо-отвору.
"""

from typing import Literal

import cadquery as cq
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from flatcraft_cad.templates.base import BendSpec, Template

# Форма перфо-отвору.
HoleShape = Literal["circle", "square"]

# Допустимі внутрішні радіуси гибу (паритет з enclosed_shelf / bend-machine spec).
ALLOWED_INNER_RADIUS_MM: tuple[float, ...] = (1.0, 2.5, 4.0, 5.0)

# Установочний (кріпильний) отвір — фіксований Ø5.5 (ADR-030).
CORNER_HOLE_DIAMETER_MM: float = 5.5


class PerforatedPanelBuildParameters(BaseModel):
    """Параметри ребристої перфо-монтажної панелі (форма отвору — параметр)."""

    model_config = ConfigDict(frozen=True, populate_by_name=True)

    length_mm: float = Field(ge=100, le=3000, description="Довжина перфо-площини (між гибами).")
    width_mm: float = Field(ge=100, le=3000, description="Ширина перфо-площини (між гибами).")
    thickness_mm: float = Field(gt=0, le=10, description="Товщина листа.")
    hole_shape: HoleShape = Field(
        default="square", description="Форма перфо-отвору (circle|square)."
    )
    hole_size_mm: float = Field(ge=3, le=30, description="Діаметр (circle) або сторона (square).")
    pitch_x_mm: float = Field(ge=10, le=200, description="Крок перфорації вздовж довжини.")
    pitch_y_mm: float = Field(ge=10, le=200, description="Крок перфорації вздовж ширини.")
    margin_mm: float = Field(ge=5, le=100, description="Мін. відступ перфорації від країв.")
    rib_height_mm: float = Field(
        ge=15, le=50, description="Висота ребра жорсткості (обов'язкове, 15–50)."
    )
    rib_corner_radius_mm: float = Field(
        default=5.0, ge=0, le=20, description="Скруглення вільних кутів ребер (R)."
    )
    corner_hole_inset_mm: float = Field(
        default=12.0, ge=8, le=50, description="Відступ центра установочного отвору від кута."
    )
    bend_radius_mm: float = Field(default=2.5, description="Внутрішній радіус гибу ребер.")
    bend_angle_deg: Literal[90] = Field(default=90, description="MVP: тільки 90°.")
    bends: tuple[BendSpec, ...] = Field(
        default=(BendSpec(direction="down"),) * 4,
        description="Напрям 4 гибів (ребра); дефолт усіх 'down' (назад).",
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
    def _bends_count_4(cls, value: tuple[BendSpec, ...]) -> tuple[BendSpec, ...]:
        if len(value) != 4:
            raise ValueError(f"bends must contain exactly 4 items (4 ribs); got {len(value)}")
        return value

    @model_validator(mode="after")
    def _rib_taller_than_bend(self) -> "PerforatedPanelBuildParameters":
        # Flat-довжина фланця = rib_height − (t + r); має бути додатна.
        if self.rib_height_mm <= self.thickness_mm + self.bend_radius_mm:
            raise ValueError(
                f"rib_height_mm ({self.rib_height_mm}) must exceed thickness+bend_radius "
                f"({self.thickness_mm}+{self.bend_radius_mm}); flange flat length non-positive"
            )
        return self


def build_perforated_panel(
    params: PerforatedPanelBuildParameters,
) -> cq.Workplane:
    """3D-модель лотка: перфо-площина + 4 ребра (фланці) ВНИЗ (union box'ів).

    Конвенція осей (як enclosed_shelf):
    - X: довжина, x ∈ [0, length_mm].
    - Y: ширина, y ∈ [0, width_mm].
    - Z: vertical; площина z ∈ [0, t], ребра z ∈ [-rib_height, 0] (вниз, назад —
      узгоджено з bend direction='down', ADR-031).

    Ребра union'яться з площиною; на кутах вони перетинаються — union дає
    валідний solid (кутова розрядка моделюється лише у розгортці, не у 3D —
    як і в enclosed_shelf). Перфорація/установочні отвори у 3D НЕ вирізаються
    (лише у DXF/PDF, як в усіх шаблонах).
    """
    t = params.thickness_mm
    length = params.length_mm
    width = params.width_mm
    rh = params.rib_height_mm

    face = cq.Workplane("XY").box(length, width, t, centered=(False, False, False))
    bottom_rib = (
        cq.Workplane("XY").box(length, t, rh, centered=(False, False, False)).translate((0, 0, -rh))
    )
    top_rib = (
        cq.Workplane("XY")
        .box(length, t, rh, centered=(False, False, False))
        .translate((0, width - t, -rh))
    )
    left_rib = (
        cq.Workplane("XY").box(t, width, rh, centered=(False, False, False)).translate((0, 0, -rh))
    )
    right_rib = (
        cq.Workplane("XY")
        .box(t, width, rh, centered=(False, False, False))
        .translate((length - t, 0, -rh))
    )
    return face.union(bottom_rib).union(top_rib).union(left_rib).union(right_rib)


class PerforatedPanelTemplate(Template[PerforatedPanelBuildParameters]):
    """Адаптер шаблонів — slug збігається з seed.ts (perforated_panel)."""

    name = "perforated_panel"

    def build(self, params: PerforatedPanelBuildParameters) -> cq.Workplane:
        return build_perforated_panel(params)
