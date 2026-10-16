"""Тести розгортки C-профілю меблевої ніжки (furniture_leg, частина 1).

Числа — golden fixture `docs/parts/furniture_leg.md` §8, звірений yurii у
SolidWorks 2022 (2026-07-28): A=70, H=100, B=35, C=45, t=2.0, R=1.0, K=0.40.

Доробка за рецензією Gemini 3.8 Flash (PR #242 → #207, журнал
`docs/promts/inputs/agy-stats/ai-furniture-leg-unfold-py.md`): перевірка
сегмента B нічим не покривалась (мутант `if flat_b <= 0:` → `if False:`
виживав), і k_factor не перевірявся на реальне використання (мутант
`k_factor=k_factor` → `k_factor=0.40` у виклику compute_bend_allowance
виживав). Обидва нижче.
"""

import math

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

    def test_межа_плоска_ділянка_h_рівно_нуль_кидає(self) -> None:
        """height_mm == 2*(bend_radius_mm + thickness_mm) → flat_h == 0, невалідно."""
        with pytest.raises(ValueError, match="segment H"):
            unfold_furniture_leg(
                plate_length_mm=70,
                height_mm=6.0,  # 2*(R+t) = 2*(1.0+2.0) = 6.0 → flat_h = 0
                foot_length_mm=35,
                width_mm=45,
                thickness_mm=2.0,
                bend_radius_mm=1.0,
            )

    def test_межа_плоска_ділянка_b_рівно_нуль_кидає(self) -> None:
        """foot_length_mm == bend_radius_mm + thickness_mm → flat_b == 0, невалідно.

        Регресія: мутант «прибрати перевірку сегмента B»
        (`if flat_b <= 0:` → `if False:`) виживав — жоден існуючий тест не
        торкався межі B.
        """
        with pytest.raises(ValueError, match="segment B"):
            unfold_furniture_leg(
                plate_length_mm=70,
                height_mm=100,
                foot_length_mm=3.0,  # R+t = 1.0+2.0 = 3.0 → flat_b = 0
                width_mm=45,
                thickness_mm=2.0,
                bend_radius_mm=1.0,
            )

    def test_занадто_мала_опорна_лапка_b_кидає(self) -> None:
        """foot_length_mm < bend_radius_mm + thickness_mm → flat_b < 0, невалідно."""
        with pytest.raises(ValueError, match="segment B"):
            unfold_furniture_leg(
                plate_length_mm=70,
                height_mm=100,
                foot_length_mm=2.0,  # < R+t = 3.0
                width_mm=45,
                thickness_mm=2.0,
                bend_radius_mm=1.0,
            )

    @pytest.mark.parametrize("k", [0.33, 0.45])
    def test_k_factor_реально_впливає_на_ba_і_довжину(self, k: float) -> None:
        """k_factor з аргумента має дійти до compute_bend_allowance, а не бути
        переписаним дефолтом 0.40 усередині unfold_furniture_leg.

        Регресія: мутант `k_factor=k_factor` → `k_factor=0.40` у виклику
        compute_bend_allowance виживав, бо golden fixture теж рахує з K=0.40
        (збіг з дефолтом), тож підміна лишалась непоміченою.

        BA = (π/180)·90°·(R + K·t) = (π/2)·(R + K·t); R=1.0, t=2.0 (§8).
        Плоскі сегменти A+H+B = (70−3) + (100−6) + (35−3) = 67+94+32 = 193 —
        не залежать від k_factor (лише від R, t), тому length = 193 + 2·BA.
        """
        r, t = 1.0, 2.0
        expected_ba = math.pi / 2 * (r + k * t)
        expected_length = 193.0 + 2 * expected_ba

        result = unfold_furniture_leg(
            plate_length_mm=70,
            height_mm=100,
            foot_length_mm=35,
            width_mm=45,
            thickness_mm=t,
            bend_radius_mm=r,
            k_factor=k,
        )

        assert result.bend_allowance_mm == pytest.approx(expected_ba, abs=1e-9)
        assert result.length_mm == pytest.approx(expected_length, abs=1e-9)
        # K=0.40 (дефолт) дає BA≈2.827 — інший k_factor мусить дати іншу BA.
        assert result.bend_allowance_mm != pytest.approx(2.827, abs=0.001)
