"""Тести corner_angle builder + hole grid distribution."""

from typing import Any

import cadquery as cq
import pytest
from pydantic import ValidationError

from flatcraft_cad.templates.corner_angle import (
    CornerAngleBuildParameters,
    CornerAngleTemplate,
    build_corner_angle,
)


def _make_params(**overrides: Any) -> CornerAngleBuildParameters:
    defaults: dict[str, Any] = {
        "leg_a_mm": 50.0,
        "leg_b_mm": 50.0,
        "bend_radius_mm": 2.5,
        "bend_angle_deg": 90,
        "width_mm": 80.0,
        "thickness_mm": 2.0,
        "hole_diameter_mm": 5.0,
        "hole_rows": 1,
        "hole_cols": 2,
        "hole_margin_mm": 12.0,
    }
    defaults.update(overrides)
    return CornerAngleBuildParameters(**defaults)


def _solid(wp: cq.Workplane) -> cq.Shape:
    obj = wp.val()
    assert isinstance(obj, cq.Shape), f"Expected cq.Shape, got {type(obj).__name__}"
    return obj


class TestParameters:
    def test_дефолтні_значення_валідні(self) -> None:
        params = _make_params()
        assert params.leg_a_mm == 50.0
        assert params.hole_cols == 2
        assert params.hole_diameter_mm == 5.0

    def test_leg_менше_20_кидає(self) -> None:
        with pytest.raises(ValidationError):
            _make_params(leg_a_mm=10.0)

    def test_невалідний_радіус_кидає(self) -> None:
        with pytest.raises(ValidationError):
            _make_params(bend_radius_mm=3.0)

    def test_hole_rows_більше_5_кидає(self) -> None:
        with pytest.raises(ValidationError):
            _make_params(hole_rows=6)

    def test_hole_diameter_менше_3_кидає(self) -> None:
        with pytest.raises(ValidationError):
            _make_params(hole_diameter_mm=2.0)

    def test_hole_rows_non_integer_кидає(self) -> None:
        with pytest.raises(ValidationError):
            _make_params(hole_rows=1.5)


class TestBuild:
    def test_bounding_box_збігається_з_l_bracket(self) -> None:
        """corner_angle 3D = L-bracket profile, отвори не вирізаються у 3D.

        Профіль у XZ → extrude по -Y (CadQuery default direction). Z — висота
        вертикальної полиці A, X — глибина горизонтальної полиці B.
        """
        params = _make_params()
        bb = _solid(build_corner_angle(params)).BoundingBox()
        assert bb.xmin == pytest.approx(0.0, abs=1e-6)
        assert bb.xmax == pytest.approx(params.leg_b_mm, abs=1e-6)
        assert bb.zmin == pytest.approx(0.0, abs=1e-6)
        assert bb.zmax == pytest.approx(params.leg_a_mm, abs=1e-6)
        # Y extrude convention: екструзія йде у негативному напрямку.
        assert abs(bb.ymax - bb.ymin) == pytest.approx(params.width_mm, abs=1e-6)

    def test_детермінізм_volume(self) -> None:
        params = _make_params()
        v1 = _solid(build_corner_angle(params)).Volume()
        v2 = _solid(build_corner_angle(params)).Volume()
        assert v1 == pytest.approx(v2, abs=1e-9)


class TestTemplate:
    def test_slug_збігається_з_seed(self) -> None:
        assert CornerAngleTemplate.name == "corner_angle"
