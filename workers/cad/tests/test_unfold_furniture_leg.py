"""Тести розгортки C-профілю меблевої ніжки (furniture_leg, частина 1).

Числа — golden fixture `docs/parts/furniture_leg.md` §8, звірений yurii у
SolidWorks 2022 (2026-07-28): A=70, H=100, B=35, C=45, t=2.0, R=1.0, K=0.40.
"""

import pytest

from flatcraft_cad.unfold import UnfoldedFurnitureLeg, unfold_furniture_leg


class TestUnfoldFurnitureLeg:
    def test_golden_fixture_довжина_і_ba(self) -> None:
        result = unfold_furniture_leg(
            plate_length_mm=70,
            height_mm=100,
            foot_length_mm=35,
            width_mm=45,
            thickness_mm=2.0,
            bend_radius_mm=1.0,
        )
        assert isinstance(result, UnfoldedFurnitureLeg)
        assert result.length_mm == pytest.approx(198.655, abs=0.01)
        assert result.bend_allowance_mm == pytest.approx(2.827, abs=0.001)
        assert result.width_mm == 45
        assert result.thickness_mm == 2.0

    def test_golden_fixture_позиції_гибу(self) -> None:
        """Центри BA-зон §8: 67.000…69.827 мм і 163.827…166.655 мм."""
        result = unfold_furniture_leg(
            plate_length_mm=70,
            height_mm=100,
            foot_length_mm=35,
            width_mm=45,
            thickness_mm=2.0,
            bend_radius_mm=1.0,
        )
        assert result.bend_positions_mm[0] == pytest.approx(68.414, abs=0.01)
        assert result.bend_positions_mm[1] == pytest.approx(165.241, abs=0.01)

    def test_занадто_мала_висота_кидає(self) -> None:
        with pytest.raises(ValueError, match="H"):
            unfold_furniture_leg(
                plate_length_mm=70,
                height_mm=5,
                foot_length_mm=35,
                width_mm=45,
                thickness_mm=3.0,
                bend_radius_mm=2.5,
            )

    def test_межа_плоска_ділянка_a_рівно_нуль_кидає(self) -> None:
        """plate_length_mm == bend_radius_mm + thickness_mm → flat_a == 0, невалідно."""
        with pytest.raises(ValueError, match="A"):
            unfold_furniture_leg(
                plate_length_mm=3.0,
                height_mm=100,
                foot_length_mm=35,
                width_mm=45,
                thickness_mm=2.0,
                bend_radius_mm=1.0,
            )
