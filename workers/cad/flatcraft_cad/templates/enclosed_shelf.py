"""Enclosed shelf — настінна полиця з 4-сторонньою cross-розгорткою.

Phase 3.0 PR 7 (ADR-027). У цьому PR (7a) — лише Pydantic-параметри.
Builder (`build_enclosed_shelf`), unfold і експорт — PR 7b/7c.

Геометрія (див. enclosed-shelf.ts для діаграми):
- bottom: width_mm × depth_mm (центральна площина).
- back: width_mm × depth_mm (вертикальна стінка, UP-bend).
- left/right: depth_mm × depth_mm (квадратні бокові, UP-bend по Y-осі).
- front rib (опц.): width_mm × stiffening_rib.height_mm (UP-bend).

`depth_mm` — спільний параметр для висоти back AND розмірів бокових стінок
(інваріант ADR-027 Рішення 5).
"""

from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

from flatcraft_cad.templates.base import BendSpec

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
