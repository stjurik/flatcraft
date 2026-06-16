"""Згортання 2D-отворів назад на 3D-грані для ізометрії (Phase 2.9.e, ADR-025).

`build_*(params)` навмисно не вирізає отвори у 3D (preview = чистий extrude;
отвори живуть лише у DXF/розгортці). Для довідкової ізометрії користувач хоче
бачити отвори, тож тут ми мапимо `unfolded.holes` (єдине джерело істини, у
координатах розгортки) на відповідні 3D-грані й вирізаємо циліндри.

Мапінг — пер-шаблонний, бо кожен шаблон по-своєму згортається:
  • perforated_panel — пласка плита, отвір ⟂ товщині (вісь Y);
  • corner_angle — L-профіль: сегмент B (горизонт.) ⟂ Z, сегмент A (вертик.) ⟂ X;
  • wall_shelf — mount holes на back-стінці ⟂ X.

Циліндри-різаки вирізаються одним boolean-викликом (`Shape.cut(*tools)`), тож
навіть сітка перфо-панелі (сотні отворів) — одна операція, без перевитрати часу.
"""

from __future__ import annotations

from dataclasses import dataclass

import cadquery as cq

from flatcraft_cad.templates.corner_angle import CornerAngleBuildParameters
from flatcraft_cad.templates.perforated_panel import PerforatedPanelBuildParameters
from flatcraft_cad.templates.wall_shelf import WallShelfBuildParameters
from flatcraft_cad.unfold import (
    UnfoldedCornerAngle,
    UnfoldedPerforatedPanel,
    UnfoldedWallShelf,
)

# Запас довжини циліндра-різака за межі товщини (щоб boolean різав чисто).
_OVERCUT_MM = 1.0


@dataclass(frozen=True)
class _HoleCut:
    """Циліндр-різак: база, вісь (одиничний напрям), довжина, радіус (мм)."""

    base: tuple[float, float, float]
    axis: tuple[float, float, float]
    depth_mm: float
    radius_mm: float


def _corner_angle_cuts(
    params: CornerAngleBuildParameters, unfolded: UnfoldedCornerAngle
) -> list[_HoleCut]:
    """L-профіль: build_corner_angle extrude'иться у XZ→Y.

    Сегмент B (горизонт. полиця): X∈[0,b], Z∈[0,t] → отвір вздовж Z.
    Сегмент A (вертик. полиця): X∈[0,t], Z∈[0,a] → отвір вздовж X.
    Розгортка: B = x∈[0,flat_b], потім BA, потім A.

    Увага: build_corner_angle extrude'иться вздовж −Y, тож ширина лежить у
    Y∈[−w,0] → координата отвору по ширині = −y_mm.
    """
    t = params.thickness_mm
    r = params.bend_radius_mm
    b = params.leg_b_mm
    flat_b = b - t - r
    ba = unfolded.bend_allowance_mm
    depth = t + 2 * _OVERCUT_MM

    cuts: list[_HoleCut] = []
    for hole in unfolded.holes:
        radius = hole.diameter_mm / 2.0
        py = -hole.y_mm
        if hole.x_mm <= flat_b + 1e-6:
            # Сегмент B: x=0 — вільний край (X=b), x=flat_b — гиб (X=t+r).
            px = b - hole.x_mm
            cuts.append(_HoleCut((px, py, -_OVERCUT_MM), (0.0, 0.0, 1.0), depth, radius))
        else:
            # Сегмент A: s від гибу (Z=t+r) до вільного краю (Z=a).
            s = hole.x_mm - (flat_b + ba)
            pz = (t + r) + s
            cuts.append(_HoleCut((-_OVERCUT_MM, py, pz), (1.0, 0.0, 0.0), depth, radius))
    return cuts


def _wall_shelf_cuts(
    params: WallShelfBuildParameters, unfolded: UnfoldedWallShelf
) -> list[_HoleCut]:
    """Mount holes на back-стінці: box(t, bh, w) → отвір вздовж X (товщина).

    Розгортка кладе back першим (x∈[0,flat_back]); x=0 — вільний верх (Y=bh),
    x=flat_back — гиб (Y≈t+r). Тож physical_Y = bh - x.
    """
    t = params.thickness_mm
    bh = params.back_height_mm
    depth = t + 2 * _OVERCUT_MM
    return [
        _HoleCut(
            (-_OVERCUT_MM, bh - hole.x_mm, hole.y_mm),
            (1.0, 0.0, 0.0),
            depth,
            hole.diameter_mm / 2.0,
        )
        for hole in unfolded.holes
    ]


def _perforated_panel_cuts(
    params: PerforatedPanelBuildParameters, unfolded: UnfoldedPerforatedPanel
) -> list[_HoleCut]:
    """Пласка плита box(length, thickness, width) → отвір вздовж Y (товщина)."""
    t = params.thickness_mm
    depth = t + 2 * _OVERCUT_MM
    return [
        _HoleCut(
            (hole.x_mm, -_OVERCUT_MM, hole.y_mm),
            (0.0, 1.0, 0.0),
            depth,
            hole.diameter_mm / 2.0,
        )
        for hole in unfolded.holes
    ]


def _apply_cuts(solid: cq.Workplane, cuts: list[_HoleCut]) -> cq.Shape:
    """Вирізає всі циліндри з solid одним boolean-викликом."""
    base = solid.val()
    assert isinstance(base, cq.Shape), "Workplane.val() має повертати Shape"
    if not cuts:
        return base
    cutters = [
        cq.Solid.makeCylinder(
            c.radius_mm,
            c.depth_mm,
            cq.Vector(*c.base),
            cq.Vector(*c.axis),
        )
        for c in cuts
    ]
    return base.cut(*cutters)


def with_isometry_holes(
    params: object,
    unfolded: object,
    solid: cq.Workplane,
) -> cq.Shape:
    """Повертає solid з вирізаними отворами для ізометрії.

    Шаблони без отворів (L-, Z-кронштейн) → solid без змін. Dispatch за типом
    params; невідомий тип → solid без змін (fail-safe, ізо просто без отворів).
    """
    if isinstance(params, CornerAngleBuildParameters) and isinstance(unfolded, UnfoldedCornerAngle):
        return _apply_cuts(solid, _corner_angle_cuts(params, unfolded))
    if isinstance(params, WallShelfBuildParameters) and isinstance(unfolded, UnfoldedWallShelf):
        return _apply_cuts(solid, _wall_shelf_cuts(params, unfolded))
    if isinstance(params, PerforatedPanelBuildParameters) and isinstance(
        unfolded, UnfoldedPerforatedPanel
    ):
        return _apply_cuts(solid, _perforated_panel_cuts(params, unfolded))
    base = solid.val()
    assert isinstance(base, cq.Shape), "Workplane.val() має повертати Shape"
    return base
