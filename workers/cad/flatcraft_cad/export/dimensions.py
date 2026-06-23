"""Габарити готового (зігнутого) виробу — Phase 2.9.b Block C.

PDF-header показує габарити РОЗГОРТКИ (плоского листа). Оператору й
замовнику корисніше знати габарити ГОТОВОЇ деталі після гибки — щоб
перевірити, чи влізе у місце монтажу. Ця pure-функція рахує bounding box
зігнутої деталі з параметрів шаблону.

Єдина конвенція осей для всіх шаблонів (свідомо консистентна, на відміну
від змішаних осей у початковому ТЗ):

  X × Y — bounding box силуету профілю (поперечний переріз деталі у площині,
          перпендикулярній до ліній гибу);
  Z     — довжина лінії гибу / extrude (= width_mm) для гнутих шаблонів;
          для плоскої перфо-панелі Z = товщина листа.

Спрощення (документоване): беремо зовнішні довжини полиць, нехтуючи
поправкою на товщину/радіус (похибка ≤ thickness, тобто ≤ 8 мм). Це
габарит-орієнтир, не точна модель — детермінований і легко перевірюваний.
"""

from __future__ import annotations

from dataclasses import dataclass

from flatcraft_cad.templates.corner_angle import CornerAngleBuildParameters
from flatcraft_cad.templates.enclosed_shelf import EnclosedShelfBuildParameters
from flatcraft_cad.templates.l_bracket import LBracketBuildParameters
from flatcraft_cad.templates.perforated_panel import PerforatedPanelBuildParameters
from flatcraft_cad.templates.perforated_panel_square import PerforatedPanelSquareBuildParameters
from flatcraft_cad.templates.wall_shelf import WallShelfBuildParameters
from flatcraft_cad.templates.z_bracket import ZBracketBuildParameters

# Будь-який підтримуваний набір параметрів шаблону.
FinishedDimsParams = (
    LBracketBuildParameters
    | CornerAngleBuildParameters
    | ZBracketBuildParameters
    | WallShelfBuildParameters
    | PerforatedPanelBuildParameters
    | PerforatedPanelSquareBuildParameters
    | EnclosedShelfBuildParameters
)


@dataclass(frozen=True)
class FinishedDimensions:
    """Bounding box готової деталі у мм (див. конвенцію осей у docstring модуля)."""

    x_mm: float
    y_mm: float
    z_mm: float


def compute_finished_dimensions(
    template_slug: str,
    params: FinishedDimsParams,
) -> FinishedDimensions:
    """Габарити зігнутого виробу за slug'ом і параметрами.

    Формули по шаблонах:
      - l_bracket / corner_angle: L-профіль з полицями leg_a, leg_b під 90° →
        (leg_a, leg_b, width). Дві полиці утворюють bbox leg_a × leg_b у
        перерізі; width — довжина вздовж лінії гибу.
      - z_bracket: дві полиці + вертикальний offset. Горизонтальний розмах =
        bottom_flange + top_flange (полиці рознесені offset'ом), вертикаль =
        offset, extrude = width → (bottom+top, offset, width).
      - wall_shelf: полиця глибиною shelf_depth (X), вертикалі back_height і
        front_lip вгору від полиці → Y = max(back_height, front_lip),
        extrude = width → (shelf_depth, max(back,lip), width).
      - perforated_panel: плоский лист → (length, width, thickness).
    """
    if isinstance(params, LBracketBuildParameters) and template_slug == "l_bracket":
        return FinishedDimensions(x_mm=params.leg_a_mm, y_mm=params.leg_b_mm, z_mm=params.width_mm)
    if isinstance(params, CornerAngleBuildParameters) and template_slug == "corner_angle":
        return FinishedDimensions(x_mm=params.leg_a_mm, y_mm=params.leg_b_mm, z_mm=params.width_mm)
    if isinstance(params, ZBracketBuildParameters) and template_slug == "z_bracket":
        return FinishedDimensions(
            x_mm=params.bottom_flange_mm + params.top_flange_mm,
            y_mm=params.offset_mm,
            z_mm=params.width_mm,
        )
    if isinstance(params, WallShelfBuildParameters) and template_slug == "wall_shelf":
        return FinishedDimensions(
            x_mm=params.shelf_depth_mm,
            y_mm=max(params.back_height_mm, params.front_lip_mm),
            z_mm=params.width_mm,
        )
    if isinstance(params, PerforatedPanelBuildParameters) and template_slug == "perforated_panel":
        return FinishedDimensions(
            x_mm=params.length_mm, y_mm=params.width_mm, z_mm=params.thickness_mm
        )
    if (
        isinstance(params, PerforatedPanelSquareBuildParameters)
        and template_slug == "perforated_panel_square"
    ):
        return FinishedDimensions(
            x_mm=params.length_mm, y_mm=params.width_mm, z_mm=params.thickness_mm
        )
    if isinstance(params, EnclosedShelfBuildParameters) and template_slug == "enclosed_shelf":
        # Bounding box зігнутого виробу:
        # X = width_mm (повна ширина).
        # Y = depth_mm (back витягнуто вертикально вгору) + thickness (bottom).
        # Z = depth_mm (front-to-back глибина полиці).
        # rib не впливає на bbox X/Y, але додає до Z front-side бік (нехтуємо).
        return FinishedDimensions(
            x_mm=params.width_mm,
            y_mm=params.depth_mm + params.thickness_mm,
            z_mm=params.depth_mm,
        )
    raise ValueError(
        f"невідома комбінація slug/параметрів для габаритів: slug={template_slug!r}, "
        f"params={type(params).__name__}"
    )


def _fmt_mm(value: float) -> str:
    """Округлює до 0.1 мм і прибирає trailing-нулі: 80.0→'80', 2.5→'2.5', 176.18→'176.2'."""
    rounded = round(value, 1)
    if rounded == int(rounded):
        return str(int(rounded))
    return f"{rounded:g}"


def format_dimensions(dims: FinishedDimensions) -> str:
    """Рядок для PDF-header: 'X × Y × Z мм' з округленням до 0.1 і без зайвих нулів."""
    return f"{_fmt_mm(dims.x_mm)} × {_fmt_mm(dims.y_mm)} × {_fmt_mm(dims.z_mm)} мм"
