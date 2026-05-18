"""Тести wall_shelf builder."""

from typing import Any

import cadquery as cq
import pytest
from pydantic import ValidationError

from flatcraft_cad.templates.wall_shelf import (
    WallShelfBuildParameters,
    WallShelfTemplate,
    build_wall_shelf,
)


def _make_params(**overrides: Any) -> WallShelfBuildParameters:
    defaults: dict[str, Any] = {
        "back_height_mm": 80.0,
        "shelf_depth_mm": 150.0,
        "front_lip_mm": 20.0,
        "bend_radius_mm": 2.5,
        "bend_angle_deg": 90,
        "width_mm": 300.0,
        "thickness_mm": 2.0,
        "mount_hole_diameter_mm": 6.0,
        "mount_hole_rows": 2,
        "mount_hole_cols": 2,
        "mount_hole_margin_mm": 15.0,
    }
    defaults.update(overrides)
    return WallShelfBuildParameters(**defaults)


def _solid(wp: cq.Workplane) -> cq.Shape:
    obj = wp.val()
    assert isinstance(obj, cq.Shape), f"Expected cq.Shape, got {type(obj).__name__}"
    return obj


class TestParameters:
    def test_дефолтні_значення_валідні(self) -> None:
        params = _make_params()
        assert params.back_height_mm == 80.0
        assert params.front_lip_mm == 20.0
        assert params.mount_hole_rows == 2

    def test_back_менше_30_кидає(self) -> None:
        with pytest.raises(ValidationError):
            _make_params(back_height_mm=20.0)

    def test_shelf_менше_50_кидає(self) -> None:
        with pytest.raises(ValidationError):
            _make_params(shelf_depth_mm=30.0)

    def test_front_lip_між_0_і_5_кидає(self) -> None:
        with pytest.raises(ValidationError):
            _make_params(front_lip_mm=3.0)

    def test_front_lip_0_дозволено(self) -> None:
        params = _make_params(front_lip_mm=0.0)
        assert params.front_lip_mm == 0.0

    def test_невалідний_радіус_кидає(self) -> None:
        with pytest.raises(ValidationError):
            _make_params(bend_radius_mm=3.0)


class TestBuild:
    def test_bounding_box_з_lip(self) -> None:
        """U-channel: shelf (sd × t) внизу + back ↑ + lip ↑.
        X: [0, shelf_depth]. Y: [0, max(back, lip)]. Z extrude: width.
        """
        params = _make_params()
        bb = _solid(build_wall_shelf(params)).BoundingBox()
        assert bb.xmin == pytest.approx(0.0, abs=1e-6)
        assert bb.xmax == pytest.approx(params.shelf_depth_mm, abs=1e-6)
        assert bb.ymin == pytest.approx(0.0, abs=1e-6)
        assert bb.ymax == pytest.approx(max(params.back_height_mm, params.front_lip_mm), abs=1e-6)
        assert bb.zmax - bb.zmin == pytest.approx(params.width_mm, abs=1e-6)

    def test_без_lip_тільки_2_сегменти(self) -> None:
        params = _make_params(front_lip_mm=0.0)
        bb = _solid(build_wall_shelf(params)).BoundingBox()
        assert bb.ymax == pytest.approx(params.back_height_mm, abs=1e-6)
        assert bb.xmax == pytest.approx(params.shelf_depth_mm, abs=1e-6)

    def test_volume_близько_до_суми_сегментів(self) -> None:
        """Volume ≈ (back + shelf + lip) × t × width − overlaps."""
        params = _make_params()
        actual = _solid(build_wall_shelf(params)).Volume()
        # Сума плит без overlap correction: back × t, shelf × t, lip × t.
        # Overlap у нижньому корнері: t² × width (back ∩ shelf).
        # Overlap у правому корнері: t² × width (shelf ∩ lip).
        t = params.thickness_mm
        w = params.width_mm
        naive = (
            params.back_height_mm * t * w
            + params.shelf_depth_mm * t * w
            + params.front_lip_mm * t * w
            - 2 * t**2 * w
        )
        assert actual == pytest.approx(naive, rel=0.05)

    def test_детермінізм(self) -> None:
        params = _make_params()
        v1 = _solid(build_wall_shelf(params)).Volume()
        v2 = _solid(build_wall_shelf(params)).Volume()
        assert v1 == pytest.approx(v2, abs=1e-9)


class TestTemplate:
    def test_slug_збігається_з_seed(self) -> None:
        assert WallShelfTemplate.name == "wall_shelf"
