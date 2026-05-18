"""Тести Z-bracket builder."""

from typing import Any

import cadquery as cq
import pytest
from pydantic import ValidationError

from flatcraft_cad.templates.z_bracket import (
    ZBracketBuildParameters,
    ZBracketTemplate,
    build_z_bracket,
)


def _make_params(**overrides: Any) -> ZBracketBuildParameters:
    defaults: dict[str, Any] = {
        "top_flange_mm": 60.0,
        "bottom_flange_mm": 60.0,
        "offset_mm": 40.0,
        "bend_radius_mm": 2.5,
        "bend_angle_deg": 90,
        "width_mm": 100.0,
        "thickness_mm": 2.0,
    }
    defaults.update(overrides)
    return ZBracketBuildParameters(**defaults)


def _solid(wp: cq.Workplane) -> cq.Shape:
    obj = wp.val()
    assert isinstance(obj, cq.Shape), f"Expected cq.Shape, got {type(obj).__name__}"
    return obj


class TestParameters:
    def test_дефолтні_значення_валідні(self) -> None:
        params = _make_params()
        assert params.top_flange_mm == 60.0
        assert params.offset_mm == 40.0
        assert params.bend_angle_deg == 90

    def test_top_flange_менше_20_кидає(self) -> None:
        with pytest.raises(ValidationError):
            _make_params(top_flange_mm=10.0)

    def test_offset_більше_500_кидає(self) -> None:
        with pytest.raises(ValidationError):
            _make_params(offset_mm=600.0)

    def test_невалідний_радіус_кидає(self) -> None:
        with pytest.raises(ValidationError):
            _make_params(bend_radius_mm=3.0)


class TestBuild:
    def test_bounding_box_охоплює_z_profile(self) -> None:
        params = _make_params()
        model = build_z_bracket(params)
        bb = _solid(model).BoundingBox()
        # X: bottom flange починається з 0; top flange зміщений на (bf-t)
        # вправо і досягає (bf-t)+tf. Для default bf=tf=60, t=2 → 118.
        expected_xmax = params.bottom_flange_mm - params.thickness_mm + params.top_flange_mm
        assert bb.xmin == pytest.approx(0.0, abs=1e-6)
        assert bb.xmax == pytest.approx(expected_xmax, abs=1e-6)
        # Y: [0, offset + t]
        assert bb.ymin == pytest.approx(0.0, abs=1e-6)
        assert bb.ymax == pytest.approx(params.offset_mm + params.thickness_mm, abs=1e-6)
        # Z: [0, width]
        assert bb.zmin == pytest.approx(0.0, abs=1e-6)
        assert bb.zmax == pytest.approx(params.width_mm, abs=1e-6)

    def test_асиметричні_полиці_змінюють_x_розмір(self) -> None:
        # top=80 виступає за bottom=60: bottom_flange-t це позиція middle x.
        # top починається з (bottom-t) і йде на top_flange → x_max =
        # bottom-t+top. При top=80, bottom=60, t=2: 60-2+80 = 138 > 60.
        params = _make_params(top_flange_mm=80.0, bottom_flange_mm=60.0)
        bb = _solid(build_z_bracket(params)).BoundingBox()
        assert bb.xmax == pytest.approx(60 - 2 + 80, abs=1e-6)

    def test_детермінізм(self) -> None:
        params = _make_params()
        v1 = _solid(build_z_bracket(params)).Volume()
        v2 = _solid(build_z_bracket(params)).Volume()
        assert v1 == pytest.approx(v2, abs=1e-9)

    def test_volume_близько_до_аналітичного(self) -> None:
        """Volume ≈ t · width · (top + bottom + offset) - overlap.
        Approximation для thin plates без точного fillet'у.
        """
        params = _make_params()
        actual = _solid(build_z_bracket(params)).Volume()
        # Sum 3 plates, без overlap correction (плити union'ані):
        # bottom = bf × t × w, vertical = t × (off+t) × w, top = tf × t × w.
        # Overlap: 2 corners по t×t×w кожен.
        naive = (
            params.bottom_flange_mm * params.thickness_mm * params.width_mm
            + params.thickness_mm * (params.offset_mm + params.thickness_mm) * params.width_mm
            + params.top_flange_mm * params.thickness_mm * params.width_mm
            - 2 * params.thickness_mm**2 * params.width_mm
        )
        assert actual == pytest.approx(naive, rel=0.05)


class TestTemplate:
    def test_slug_збігається_з_seed(self) -> None:
        assert ZBracketTemplate.name == "z_bracket"
