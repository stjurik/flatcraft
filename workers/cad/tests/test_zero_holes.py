"""Тести для випадку з нульовою кількістю отворів."""

from flatcraft_cad.templates.corner_angle import CornerAngleBuildParameters
from flatcraft_cad.templates.wall_shelf import WallShelfBuildParameters
from flatcraft_cad.unfold import _distribute, unfold_corner_angle, unfold_wall_shelf


def test_distribute_zero() -> None:
    """_distribute(n=0) має повертати порожній кортеж."""
    assert _distribute(0, 0, 100, 10) == ()
    assert _distribute(-1, 0, 100, 10) == ()


def test_corner_angle_zero_holes() -> None:
    """Corner angle з hole_rows=0 або hole_cols=0 має бути без отворів."""
    params = CornerAngleBuildParameters(
        legA_mm=50,
        legB_mm=50,
        bend_radius_mm=2.5,
        width_mm=80,
        thickness_mm=2.0,
        hole_diameter_mm=5,
        hole_rows=0,
        hole_cols=2,
        hole_margin_mm=12,
    )
    result = unfold_corner_angle(params, k_factor=0.4)
    assert len(result.holes) == 0

    params2 = CornerAngleBuildParameters(
        legA_mm=50,
        legB_mm=50,
        bend_radius_mm=2.5,
        width_mm=80,
        thickness_mm=2.0,
        hole_diameter_mm=5,
        hole_rows=2,
        hole_cols=0,
        hole_margin_mm=12,
    )
    result2 = unfold_corner_angle(params2, k_factor=0.4)
    assert len(result2.holes) == 0


def test_wall_shelf_zero_holes() -> None:
    """Wall shelf з mount_hole_rows=0 або mount_hole_cols=0 має бути без отворів."""
    params = WallShelfBuildParameters(
        back_height_mm=80,
        shelf_depth_mm=150,
        front_lip_mm=20,
        bend_radius_mm=2.5,
        width_mm=300,
        thickness_mm=2.0,
        mount_hole_diameter_mm=6,
        mount_hole_rows=0,
        mount_hole_cols=2,
        mount_hole_margin_mm=15,
    )
    result = unfold_wall_shelf(params, k_factor=0.4)
    assert len(result.holes) == 0
