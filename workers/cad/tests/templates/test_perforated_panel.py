"""Тести perforated_panel builder."""

from typing import Any

import cadquery as cq
import pytest
from pydantic import ValidationError

from flatcraft_cad.templates.perforated_panel import (
    PerforatedPanelBuildParameters,
    PerforatedPanelTemplate,
    build_perforated_panel,
)


def _make_params(**overrides: Any) -> PerforatedPanelBuildParameters:
    defaults: dict[str, Any] = {
        "length_mm": 200.0,
        "width_mm": 150.0,
        "thickness_mm": 2.0,
        "hole_diameter_mm": 8.0,
        "pitch_x_mm": 20.0,
        "pitch_y_mm": 20.0,
        "margin_mm": 15.0,
    }
    defaults.update(overrides)
    return PerforatedPanelBuildParameters(**defaults)


def _solid(wp: cq.Workplane) -> cq.Shape:
    obj = wp.val()
    assert isinstance(obj, cq.Shape), f"Expected cq.Shape, got {type(obj).__name__}"
    return obj


class TestParameters:
    def test_дефолтні_значення_валідні(self) -> None:
        params = _make_params()
        assert params.length_mm == 200.0
        assert params.pitch_x_mm == 20.0

    def test_length_менше_100_кидає(self) -> None:
        with pytest.raises(ValidationError):
            _make_params(length_mm=50.0)

    def test_pitch_x_менше_10_кидає(self) -> None:
        with pytest.raises(ValidationError):
            _make_params(pitch_x_mm=5.0)

    def test_hole_diameter_більше_30_кидає(self) -> None:
        with pytest.raises(ValidationError):
            _make_params(hole_diameter_mm=35.0)


class TestBuild:
    def test_bounding_box_збігається_з_box(self) -> None:
        """3D = плоский box(length × thickness × width). Отвори лише у DXF."""
        params = _make_params()
        bb = _solid(build_perforated_panel(params)).BoundingBox()
        assert bb.xmin == pytest.approx(0.0, abs=1e-6)
        assert bb.xmax == pytest.approx(params.length_mm, abs=1e-6)
        assert bb.ymin == pytest.approx(0.0, abs=1e-6)
        assert bb.ymax == pytest.approx(params.thickness_mm, abs=1e-6)
        assert bb.zmin == pytest.approx(0.0, abs=1e-6)
        assert bb.zmax == pytest.approx(params.width_mm, abs=1e-6)

    def test_volume_дорівнює_l_w_t(self) -> None:
        params = _make_params()
        actual = _solid(build_perforated_panel(params)).Volume()
        expected = params.length_mm * params.width_mm * params.thickness_mm
        assert actual == pytest.approx(expected, abs=1e-6)

    def test_детермінізм(self) -> None:
        params = _make_params()
        v1 = _solid(build_perforated_panel(params)).Volume()
        v2 = _solid(build_perforated_panel(params)).Volume()
        assert v1 == pytest.approx(v2, abs=1e-9)


class TestTemplate:
    def test_slug_збігається_з_seed(self) -> None:
        assert PerforatedPanelTemplate.name == "perforated_panel"
