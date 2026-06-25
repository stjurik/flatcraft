"""Перфорована МОНТАЖНА панель (квадратні отвори + ребра жорсткості) — ADR-030.

Раніше `perforated_panel_square` був пласким листом (Phase 3.0 PR 5). ADR-030
переосмислює його на ГНУТИЙ ЛОТОК: усі 4 сторони зміцнені ребрами (фланцями 90°),
у 4 кутах площини — установочні отвори Ø5.5 для кріплення панелі у шафу.
**Ребра обов'язкові** (не опційні) — це визначальна риса виробу.

Геометрія (розгортка — хрест/плюс, деталі у unfold.py):
- центральна перфо-площина length×width (між лініями гибу);
- 4 фланці, гнуті 90° назад (UP у 3D), висота `rib_height_mm`, однакова;
- вільні кути фланців скруглені R=`rib_corner_radius_mm` (дефолт 5);
- кутова розрядка автоматична (відкриті кути — фланці не накладаються при гибі);
- 4 установочні отвори Ø5.5 на площині, inset `corner_hole_inset_mm` від кутів.

Круглий `perforated_panel` лишається ПЛАСКИМ (ADR-030 поза скоупом).

Параметр `hole_size_mm` — side length квадратного перфо-отвору.
"""

from typing import Literal

import cadquery as cq
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from flatcraft_cad.templates.base import BendSpec, Template

# Допустимі внутрішні радіуси гибу (паритет з enclosed_shelf / bend-machine spec).
ALLOWED_INNER_RADIUS_MM: tuple[float, ...] = (1.0, 2.5, 4.0, 5.0)

# Установочний (кріпильний) отвір — фіксований Ø5.5 (ADR-030).
CORNER_HOLE_DIAMETER_MM: float = 5.5


class PerforatedPanelSquareBuildParameters(BaseModel):
    """Параметри ребристої перфо-монтажної панелі (квадратні отвори)."""

    model_config = ConfigDict(frozen=True, populate_by_name=True)

    length_mm: float = Field(ge=100, le=3000, description="Довжина перфо-площини (між гибами).")
    width_mm: float = Field(ge=100, le=3000, description="Ширина перфо-площини (між гибами).")
    thickness_mm: float = Field(gt=0, le=10, description="Товщина листа.")
    hole_size_mm: float = Field(ge=3, le=30, description="Сторона квадратного отвору.")
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
    def _rib_taller_than_bend(self) -> "PerforatedPanelSquareBuildParameters":
        # Flat-довжина фланця = rib_height − (t + r); має бути додатна.
        if self.rib_height_mm <= self.thickness_mm + self.bend_radius_mm:
            raise ValueError(
                f"rib_height_mm ({self.rib_height_mm}) must exceed thickness+bend_radius "
                f"({self.thickness_mm}+{self.bend_radius_mm}); flange flat length non-positive"
            )
        return self


def build_perforated_panel_square(
    params: PerforatedPanelSquareBuildParameters,
) -> cq.Workplane:
    """3D-модель лотка: перфо-площина + 4 ребра (фланці) вгору (union box'ів).

    Конвенція осей (як enclosed_shelf):
    - X: довжина, x ∈ [0, length_mm].
    - Y: ширина, y ∈ [0, width_mm].
    - Z: vertical; площина z ∈ [0, t], ребра z ∈ [t, t+rib_height].

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
        cq.Workplane("XY").box(length, t, rh, centered=(False, False, False)).translate((0, 0, t))
    )
    top_rib = (
        cq.Workplane("XY")
        .box(length, t, rh, centered=(False, False, False))
        .translate((0, width - t, t))
    )
    left_rib = (
        cq.Workplane("XY").box(t, width, rh, centered=(False, False, False)).translate((0, 0, t))
    )
    right_rib = (
        cq.Workplane("XY")
        .box(t, width, rh, centered=(False, False, False))
        .translate((length - t, 0, t))
    )
    return face.union(bottom_rib).union(top_rib).union(left_rib).union(right_rib)


class PerforatedPanelSquareTemplate(Template[PerforatedPanelSquareBuildParameters]):
    """Адаптер шаблонів — slug збігається з seed.ts (perforated_panel_square)."""

    name = "perforated_panel_square"

    def build(self, params: PerforatedPanelSquareBuildParameters) -> cq.Workplane:
        return build_perforated_panel_square(params)
