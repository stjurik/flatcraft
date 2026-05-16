"""Тести параметричної моделі L-кронштейна."""

import math
from typing import Any

import cadquery as cq
import pytest
from pydantic import ValidationError

from flatcraft_cad.templates.l_bracket import (
    LBracketBuildParameters,
    LBracketTemplate,
    build_l_bracket,
)


def _make_params(**overrides: Any) -> LBracketBuildParameters:
    """Базовий валідний preset; тести лиш перекривають окремі поля."""
    defaults: dict[str, Any] = {
        "leg_a_mm": 60.0,
        "leg_b_mm": 60.0,
        "bend_radius_mm": 2.5,
        "bend_angle_deg": 90,
        "width_mm": 100.0,
        "thickness_mm": 2.0,
    }
    defaults.update(overrides)
    return LBracketBuildParameters(**defaults)


def _solid(wp: cq.Workplane) -> cq.Shape:
    """Звужує тип результату extrude до cq.Shape (для типобезпечного
    доступу до Volume()/Faces() у тестах)."""
    obj = wp.val()
    assert isinstance(obj, cq.Shape), f"Expected cq.Shape, got {type(obj).__name__}"
    return obj


class TestParameters:
    def test_дефолтні_значення_валідні(self) -> None:
        params = _make_params()
        assert params.leg_a_mm == 60.0
        assert params.bend_radius_mm == 2.5
        assert params.bend_angle_deg == 90

    def test_приймає_payload_з_ts_alias_camel_case(self) -> None:
        params = LBracketBuildParameters.model_validate(
            {
                "legA_mm": 80,
                "legB_mm": 40,
                "bend_radius_mm": 2.5,
                "bend_angle_deg": 90,
                "width_mm": 150,
                "thickness_mm": 2,
            }
        )
        assert params.leg_a_mm == 80
        assert params.leg_b_mm == 40

    def test_leg_a_менше_20_кидає(self) -> None:
        with pytest.raises(ValidationError):
            _make_params(leg_a_mm=10.0)

    def test_leg_b_більше_500_кидає(self) -> None:
        with pytest.raises(ValidationError):
            _make_params(leg_b_mm=600.0)

    def test_недозволений_радіус_кидає(self) -> None:
        with pytest.raises(ValidationError):
            _make_params(bend_radius_mm=3.0)  # не у {1, 2.5, 4, 5}

    def test_кут_крім_90_кидає(self) -> None:
        with pytest.raises(ValidationError):
            _make_params(bend_angle_deg=60)

    def test_thickness_нульовий_кидає(self) -> None:
        with pytest.raises(ValidationError):
            _make_params(thickness_mm=0)

    def test_frozen_не_можна_мутувати(self) -> None:
        params = _make_params()
        with pytest.raises(ValidationError):
            params.leg_a_mm = 100.0


class TestBuild:
    @pytest.mark.parametrize(
        ("leg_a", "leg_b", "thickness", "radius", "width"),
        [
            (60.0, 60.0, 2.0, 2.5, 100.0),  # стандарт
            (40.0, 80.0, 1.5, 2.5, 200.0),  # асиметричні полиці
            (120.0, 80.0, 3.0, 4.0, 150.0),  # товстіша
        ],
    )
    def test_bounding_box_відповідає_розмірам(
        self,
        leg_a: float,
        leg_b: float,
        thickness: float,
        radius: float,
        width: float,
    ) -> None:
        params = _make_params(
            leg_a_mm=leg_a,
            leg_b_mm=leg_b,
            thickness_mm=thickness,
            bend_radius_mm=radius,
            width_mm=width,
        )
        model = build_l_bracket(params)
        bb = _solid(model).BoundingBox()
        # X: 0..leg_b (полиця B горизонтальна)
        # Y: -width..0 (extrude по нормалі XZ → -Y у CadQuery default)
        # Z: 0..leg_a (полиця A вертикальна)
        assert bb.xmin == pytest.approx(0.0, abs=1e-6)
        assert bb.xmax == pytest.approx(leg_b, abs=1e-6)
        assert abs(bb.ymax - bb.ymin) == pytest.approx(width, abs=1e-6)
        assert bb.zmin == pytest.approx(0.0, abs=1e-6)
        assert bb.zmax == pytest.approx(leg_a, abs=1e-6)

    def test_volume_близько_до_аналітичного(self) -> None:
        """Profile area ≈ t·(leg_a + leg_b − t) для квадратного кута;
        дуга трохи зменшує матеріал у куті — допуск 5%.
        """
        params = _make_params(
            leg_a_mm=60.0,
            leg_b_mm=60.0,
            thickness_mm=2.0,
            bend_radius_mm=2.5,
            width_mm=100.0,
        )
        model = build_l_bracket(params)
        actual_volume = _solid(model).Volume()
        naive_area = params.thickness_mm * (params.leg_a_mm + params.leg_b_mm - params.thickness_mm)
        naive_volume = naive_area * params.width_mm
        assert math.isclose(actual_volume, naive_volume, rel_tol=0.05)

    def test_детермінізм_однаковий_seed_однакова_геометрія(self) -> None:
        """CLAUDE.md §2.4: однакові параметри → байт-у-байт однакова
        геометрія. Перевіряємо через volume і кількість faces.
        """
        params = _make_params()
        v1 = _solid(build_l_bracket(params))
        v2 = _solid(build_l_bracket(params))
        assert v1.Volume() == pytest.approx(v2.Volume(), abs=1e-9)
        # 2D-профіль з 6 ліній + 1 arc = 7 segments. Extrude:
        # 2 торцеві грані (top + bottom) + 7 бокових = 9 faces.
        assert len(v1.Faces()) == len(v2.Faces()) == 9

    def test_повертає_cq_workplane(self) -> None:
        params = _make_params()
        result = build_l_bracket(params)
        assert isinstance(result, cq.Workplane)


class TestTemplate:
    def test_slug_збігається_з_seed(self) -> None:
        assert LBracketTemplate.name == "l_bracket"

    def test_build_делегує_у_build_l_bracket(self) -> None:
        tpl = LBracketTemplate()
        params = _make_params()
        result = tpl.build(params)
        expected = build_l_bracket(params)
        assert _solid(result).Volume() == pytest.approx(_solid(expected).Volume(), abs=1e-9)
