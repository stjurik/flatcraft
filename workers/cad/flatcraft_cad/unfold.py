"""Розгортка sheet-metal моделі у плоский патерн.

Формула bend allowance (BA) — це довжина матеріалу по нейтральній осі гиба:
    BA = (π/180) · angle_deg · (R + K · t)
де R — внутрішній радіус, t — товщина, K — K-фактор (з cad-engine).

Для L-кронштейна з одним 90° гибом розгортка — це смужка довжиною
    L = (leg_a − t − R) + BA + (leg_b − t − R)
з лінією гиба у центрі BA-сегмента.

Для Z-кронштейна (Phase 2.10) — два 90° гиби, 3 плоских сегменти,
2 лінії гиба:
    L = (bottom − t − R) + BA + (offset − t − R) + BA + (top − t − R)

CadQuery-розгортка через `Workplane.shell()` поки не використовується —
формула достатня для регулярних гнутих профілів.
"""

import math
from dataclasses import dataclass

from flatcraft_cad.templates.l_bracket import LBracketBuildParameters
from flatcraft_cad.templates.z_bracket import ZBracketBuildParameters


@dataclass(frozen=True)
class UnfoldedLBracket:
    """Результат розгортки L-кронштейна."""

    length_mm: float
    """Повна розгорнута довжина (від лівого до правого краю)."""

    width_mm: float
    """= params.width_mm — не змінюється при розгортці."""

    thickness_mm: float
    """= params.thickness_mm — товщина листа."""

    bend_position_mm: float
    """Відстань від лівого краю до лінії гиба (центр BA-сегмента)."""

    bend_allowance_mm: float
    """Довжина матеріалу у bend region (по нейтральній осі)."""


@dataclass(frozen=True)
class UnfoldedZBracket:
    """Результат розгортки Z-кронштейна. 2 bends → 2 bend positions."""

    length_mm: float
    width_mm: float
    thickness_mm: float
    bend_positions_mm: tuple[float, float]
    """Відстані від лівого краю до кожної з двох ліній гиба."""

    bend_allowance_mm: float
    """Однаковий BA для обох гибів (однаковий angle/R/t/K)."""


def compute_bend_allowance(
    angle_deg: float,
    inner_radius_mm: float,
    thickness_mm: float,
    k_factor: float,
) -> float:
    """BA = (π/180) · angle · (R + K·t).

    Невалідні діапазони — ValueError (мають відсіюватись TS-валідатором
    до виклику воркера).
    """
    if not 0.0 < angle_deg <= 180.0:
        raise ValueError(f"angle_deg must be in (0, 180]; got {angle_deg}")
    if inner_radius_mm < 0.0:
        raise ValueError(f"inner_radius_mm must be >= 0; got {inner_radius_mm}")
    if thickness_mm <= 0.0:
        raise ValueError(f"thickness_mm must be > 0; got {thickness_mm}")
    if not 0.0 < k_factor <= 1.0:
        raise ValueError(f"k_factor must be in (0, 1]; got {k_factor}")

    return math.radians(angle_deg) * (inner_radius_mm + k_factor * thickness_mm)


def unfold_l_bracket(params: LBracketBuildParameters, k_factor: float) -> UnfoldedLBracket:
    """Розгортає L-кронштейн у плоский патерн.

    K-фактор обчислюється у TypeScript (packages/cad-engine/k-factor.ts)
    і передається сюди — воркер не дублює довідник.
    """
    t = params.thickness_mm
    r = params.bend_radius_mm
    flat_a = params.leg_a_mm - t - r
    flat_b = params.leg_b_mm - t - r

    if flat_a <= 0 or flat_b <= 0:
        raise ValueError(
            f"L-bracket legs too short for bend (leg_a={params.leg_a_mm}, "
            f"leg_b={params.leg_b_mm}, t={t}, R={r}): flat segments would be non-positive"
        )

    ba = compute_bend_allowance(
        angle_deg=float(params.bend_angle_deg),
        inner_radius_mm=r,
        thickness_mm=t,
        k_factor=k_factor,
    )

    return UnfoldedLBracket(
        length_mm=flat_b + ba + flat_a,
        width_mm=params.width_mm,
        thickness_mm=t,
        bend_position_mm=flat_b + ba / 2,
        bend_allowance_mm=ba,
    )


def unfold_z_bracket(params: ZBracketBuildParameters, k_factor: float) -> UnfoldedZBracket:
    """Розгортає Z-кронштейн у смужку з 3 плоских сегментів + 2 BA.

    Конвенція ordering: bottom → bend1 → middle → bend2 → top.
    Позиції bend lines — центри BA-сегментів.
    """
    t = params.thickness_mm
    r = params.bend_radius_mm
    flat_bottom = params.bottom_flange_mm - t - r
    flat_middle = params.offset_mm - t - r
    flat_top = params.top_flange_mm - t - r

    if flat_bottom <= 0 or flat_middle <= 0 or flat_top <= 0:
        raise ValueError(
            f"Z-bracket segments too short for bend (top={params.top_flange_mm}, "
            f"bottom={params.bottom_flange_mm}, offset={params.offset_mm}, t={t}, R={r}): "
            "one or more flat segments would be non-positive"
        )

    ba = compute_bend_allowance(
        angle_deg=float(params.bend_angle_deg),
        inner_radius_mm=r,
        thickness_mm=t,
        k_factor=k_factor,
    )

    bend1 = flat_bottom + ba / 2
    bend2 = flat_bottom + ba + flat_middle + ba / 2

    return UnfoldedZBracket(
        length_mm=flat_bottom + ba + flat_middle + ba + flat_top,
        width_mm=params.width_mm,
        thickness_mm=t,
        bend_positions_mm=(bend1, bend2),
        bend_allowance_mm=ba,
    )
