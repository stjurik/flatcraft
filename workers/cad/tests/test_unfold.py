"""Тести алгоритму розгортки з K-фактором."""

import math

import pytest

from flatcraft_cad.templates.corner_angle import CornerAngleBuildParameters
from flatcraft_cad.templates.l_bracket import LBracketBuildParameters
from flatcraft_cad.templates.wall_shelf import WallShelfBuildParameters
from flatcraft_cad.templates.z_bracket import ZBracketBuildParameters
from flatcraft_cad.unfold import (
    UnfoldedCornerAngle,
    UnfoldedLBracket,
    UnfoldedWallShelf,
    UnfoldedZBracket,
    _distribute,
    compute_bend_allowance,
    unfold_corner_angle,
    unfold_l_bracket,
    unfold_wall_shelf,
    unfold_z_bracket,
)


class TestBendAllowance:
    def test_формула_ba_по_нейтральній_лінії(self) -> None:
        """BA = (π/180) · angle · (R + K·t).
        Ручний розрахунок: angle=90, R=2.5, t=2, K=0.4
        → BA = (π/2) · (2.5 + 0.8) = (π/2) · 3.3 ≈ 5.1836.
        """
        ba = compute_bend_allowance(
            angle_deg=90.0, inner_radius_mm=2.5, thickness_mm=2.0, k_factor=0.4
        )
        expected = (math.pi / 2) * 3.3
        assert ba == pytest.approx(expected, abs=1e-9)

    def test_кут_60_градусів(self) -> None:
        ba = compute_bend_allowance(
            angle_deg=60.0, inner_radius_mm=2.0, thickness_mm=1.5, k_factor=0.5
        )
        expected = (math.pi / 3) * (2.0 + 0.75)
        assert ba == pytest.approx(expected, abs=1e-9)

    def test_кут_180_означає_півколо(self) -> None:
        # 180° гиб → довжина BA = π × (R + K·t).
        ba = compute_bend_allowance(
            angle_deg=180.0, inner_radius_mm=1.0, thickness_mm=1.0, k_factor=0.4
        )
        assert ba == pytest.approx(math.pi * 1.4, abs=1e-9)

    @pytest.mark.parametrize("bad_angle", [-1.0, 0.0, 181.0])
    def test_невалідний_кут_кидає(self, bad_angle: float) -> None:
        with pytest.raises(ValueError, match="angle"):
            compute_bend_allowance(
                angle_deg=bad_angle, inner_radius_mm=2.5, thickness_mm=2.0, k_factor=0.4
            )

    def test_невалідний_радіус_кидає(self) -> None:
        with pytest.raises(ValueError, match="inner_radius"):
            compute_bend_allowance(
                angle_deg=90, inner_radius_mm=-1.0, thickness_mm=2.0, k_factor=0.4
            )

    def test_невалідна_товщина_кидає(self) -> None:
        with pytest.raises(ValueError, match="thickness"):
            compute_bend_allowance(
                angle_deg=90, inner_radius_mm=2.0, thickness_mm=0.0, k_factor=0.4
            )

    def test_невалідний_k_кидає(self) -> None:
        with pytest.raises(ValueError, match="k_factor"):
            compute_bend_allowance(
                angle_deg=90, inner_radius_mm=2.0, thickness_mm=2.0, k_factor=1.5
            )


class TestUnfoldLBracket:
    def _params(self, **overrides: float) -> LBracketBuildParameters:
        defaults: dict[str, float] = {
            "leg_a_mm": 60.0,
            "leg_b_mm": 60.0,
            "bend_radius_mm": 2.5,
            "bend_angle_deg": 90,
            "width_mm": 100.0,
            "thickness_mm": 2.0,
        }
        defaults.update(overrides)
        return LBracketBuildParameters(**defaults)  # type: ignore[arg-type]

    def test_розгортка_60_60_t2_r25_k04(self) -> None:
        """Конвенція: розгортка починається з полиці B, потім bend, потім полиця A.
        L = (leg_b − t − R) + BA + (leg_a − t − R)
          = (60 − 2 − 2.5) + (π/2)(2.5 + 0.4·2) + (60 − 2 − 2.5)
          ≈ 55.5 + 5.1836 + 55.5 = 116.1836 мм
        Лінія гиба — центр BA-сегмента від лівого краю.
        """
        result = unfold_l_bracket(self._params(), k_factor=0.4)
        assert isinstance(result, UnfoldedLBracket)
        expected_ba = (math.pi / 2) * 3.3
        expected_length = 55.5 + expected_ba + 55.5
        assert result.length_mm == pytest.approx(expected_length, abs=1e-9)
        assert result.width_mm == pytest.approx(100.0, abs=1e-9)
        assert result.bend_allowance_mm == pytest.approx(expected_ba, abs=1e-9)
        assert result.bend_position_mm == pytest.approx(55.5 + expected_ba / 2, abs=1e-9)
        assert result.thickness_mm == 2.0

    def test_асиметричні_полиці_конвенція_b_спочатку(self) -> None:
        """leg_a=40, leg_b=80, t=1.5, R=2.5, K=0.4.
        Розгортка: спочатку flat_b=76, потім BA, потім flat_a=36.
        Bend position = flat_b + BA/2.
        """
        params = self._params(leg_a_mm=40.0, leg_b_mm=80.0, thickness_mm=1.5, width_mm=200.0)
        result = unfold_l_bracket(params, k_factor=0.4)
        expected_ba = (math.pi / 2) * (2.5 + 0.4 * 1.5)
        expected_length = (80 - 1.5 - 2.5) + expected_ba + (40 - 1.5 - 2.5)
        assert result.length_mm == pytest.approx(expected_length, abs=1e-9)
        assert result.bend_position_mm == pytest.approx(
            (80 - 1.5 - 2.5) + expected_ba / 2, abs=1e-9
        )

    def test_розгортка_зберігає_площу_приблизно(self) -> None:
        """Площа розгорнутого аркуша має бути близько до площі профілю
        L-bracket·width."""
        params = self._params()
        result = unfold_l_bracket(params, k_factor=0.4)
        unfolded_volume = result.length_mm * result.width_mm * result.thickness_mm
        profile_area = params.thickness_mm * (
            params.leg_a_mm + params.leg_b_mm - params.thickness_mm
        )
        bracket_volume = profile_area * params.width_mm
        assert unfolded_volume == pytest.approx(bracket_volume, rel=0.03)

    def test_k_фактор_впливає_на_довжину(self) -> None:
        """Більший K → довша розгортка (більше матеріалу у bend region)."""
        params = self._params()
        small_k = unfold_l_bracket(params, k_factor=0.3)
        big_k = unfold_l_bracket(params, k_factor=0.5)
        assert big_k.length_mm > small_k.length_mm

    def test_детермінізм(self) -> None:
        params = self._params()
        a = unfold_l_bracket(params, k_factor=0.4)
        b = unfold_l_bracket(params, k_factor=0.4)
        assert a == b

    def test_закороткі_полиці_кидають(self) -> None:
        """leg_a − t − R ≤ 0: плоский сегмент відсутній → ValueError."""
        # leg_a=20 (мінімум валідації), t=8, R=5 → 20 - 8 - 5 = 7 > 0, OK.
        # Зробимо явно small: t=10, R=5 (макс), leg=20 → 20-10-5=5 > 0
        # Меньше неможливо через Pydantic constraints.
        # Достатньо синтетичних значень через model_construct (обхід валідації).
        params = LBracketBuildParameters.model_construct(
            leg_a_mm=10.0,
            leg_b_mm=60.0,
            bend_radius_mm=5.0,
            bend_angle_deg=90,
            width_mm=100.0,
            thickness_mm=8.0,
        )
        with pytest.raises(ValueError, match="too short"):
            unfold_l_bracket(params, k_factor=0.4)


class TestUnfoldZBracket:
    def _params(self, **overrides: float) -> ZBracketBuildParameters:
        defaults: dict[str, float] = {
            "top_flange_mm": 60.0,
            "bottom_flange_mm": 60.0,
            "offset_mm": 40.0,
            "bend_radius_mm": 2.5,
            "bend_angle_deg": 90,
            "width_mm": 100.0,
            "thickness_mm": 2.0,
        }
        defaults.update(overrides)
        return ZBracketBuildParameters(**defaults)  # type: ignore[arg-type]

    def test_симетричний_z_60_40_60_t2_r25(self) -> None:
        result = unfold_z_bracket(self._params(), k_factor=0.4)
        assert isinstance(result, UnfoldedZBracket)
        # flat_bottom = flat_top = 60 - 2 - 2.5 = 55.5
        # flat_middle = 40 - 2 - 2.5 = 35.5
        # BA = (π/2)·(2.5 + 0.4·2) = (π/2)·3.3 ≈ 5.1836
        expected_ba = (math.pi / 2) * 3.3
        expected_length = 55.5 + expected_ba + 35.5 + expected_ba + 55.5
        assert result.length_mm == pytest.approx(expected_length, abs=1e-9)
        assert result.bend_allowance_mm == pytest.approx(expected_ba, abs=1e-9)
        # bend1 = flat_bottom + BA/2; bend2 = flat_bottom + BA + flat_middle + BA/2
        assert result.bend_positions_mm[0] == pytest.approx(55.5 + expected_ba / 2, abs=1e-9)
        assert result.bend_positions_mm[1] == pytest.approx(
            55.5 + expected_ba + 35.5 + expected_ba / 2, abs=1e-9
        )

    def test_асиметричні_полиці(self) -> None:
        # top=80, bottom=40, offset=60, t=1.5, R=2.5
        params = self._params(
            top_flange_mm=80.0, bottom_flange_mm=40.0, offset_mm=60.0, thickness_mm=1.5
        )
        result = unfold_z_bracket(params, k_factor=0.4)
        expected_ba = (math.pi / 2) * (2.5 + 0.4 * 1.5)
        flat_b = 40 - 1.5 - 2.5
        flat_m = 60 - 1.5 - 2.5
        flat_t = 80 - 1.5 - 2.5
        expected_length = flat_b + expected_ba + flat_m + expected_ba + flat_t
        assert result.length_mm == pytest.approx(expected_length, abs=1e-9)
        # bend1 — після bottom
        assert result.bend_positions_mm[0] == pytest.approx(
            (40 - 1.5 - 2.5) + expected_ba / 2, abs=1e-9
        )

    def test_закороткий_offset_кидає(self) -> None:
        params = ZBracketBuildParameters.model_construct(
            top_flange_mm=60.0,
            bottom_flange_mm=60.0,
            offset_mm=5.0,
            bend_radius_mm=5.0,
            bend_angle_deg=90,
            width_mm=100.0,
            thickness_mm=8.0,
        )
        with pytest.raises(ValueError, match="too short"):
            unfold_z_bracket(params, k_factor=0.4)

    def test_детермінізм(self) -> None:
        params = self._params()
        a = unfold_z_bracket(params, k_factor=0.4)
        b = unfold_z_bracket(params, k_factor=0.4)
        assert a == b

    def test_k_фактор_впливає_на_довжину(self) -> None:
        params = self._params()
        small = unfold_z_bracket(params, k_factor=0.3)
        big = unfold_z_bracket(params, k_factor=0.5)
        assert big.length_mm > small.length_mm


class TestDistribute:
    def test_n_1_повертає_центр_сегмента(self) -> None:
        assert _distribute(1, 0.0, 100.0, 12.0) == (50.0,)

    def test_n_2_повертає_крайні_позиції_з_margin(self) -> None:
        assert _distribute(2, 0.0, 100.0, 12.0) == (12.0, 88.0)

    def test_n_3_рівні_інтервали(self) -> None:
        result = _distribute(3, 0.0, 100.0, 10.0)
        assert result == (10.0, 50.0, 90.0)

    def test_надто_великий_margin_кидає(self) -> None:
        with pytest.raises(ValueError, match="margin"):
            _distribute(3, 0.0, 20.0, 15.0)  # 15 > (20-15)


class TestUnfoldCornerAngle:
    def _params(self, **overrides: float | int) -> CornerAngleBuildParameters:
        defaults: dict[str, float | int] = {
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
        return CornerAngleBuildParameters(**defaults)  # type: ignore[arg-type]

    def test_розгортка_50_50_t2_r25_k04(self) -> None:
        """L = (leg_b − t − R) + BA + (leg_a − t − R) = 45.5 + BA + 45.5."""
        result = unfold_corner_angle(self._params(), k_factor=0.4)
        assert isinstance(result, UnfoldedCornerAngle)
        expected_ba = (math.pi / 2) * 3.3
        expected_length = 45.5 + expected_ba + 45.5
        assert result.length_mm == pytest.approx(expected_length, abs=1e-9)
        assert result.bend_position_mm == pytest.approx(45.5 + expected_ba / 2, abs=1e-9)

    def test_grid_1x2_дає_4_отвори(self) -> None:
        """rows=1 × cols=2 × 2 полиці = 4 отвори."""
        result = unfold_corner_angle(self._params(), k_factor=0.4)
        assert len(result.holes) == 4
        # rows=1 → y = width/2 = 40 для всіх отворів.
        for h in result.holes:
            assert h.y_mm == pytest.approx(40.0, abs=1e-9)
            assert h.diameter_mm == 5.0

    def test_grid_2x3_дає_12_отворів(self) -> None:
        result = unfold_corner_angle(self._params(hole_rows=2, hole_cols=3), k_factor=0.4)
        assert len(result.holes) == 12

    def test_grid_розподіляється_симетрично_по_полицях(self) -> None:
        """B (0..flat_b=45.5) і A (flat_b+BA..length): однакові x-offsets."""
        params = self._params(hole_cols=2, hole_rows=1, hole_margin_mm=10.0)
        result = unfold_corner_angle(params, k_factor=0.4)
        # 4 отвори: 2 на B (x=10, 35.5), 2 на A (зсунуті на flat_b+BA).
        ba = result.bend_allowance_mm
        b_xs = sorted(h.x_mm for h in result.holes if h.x_mm < 45.5)
        a_xs = sorted(h.x_mm for h in result.holes if h.x_mm > 45.5)
        assert b_xs == pytest.approx([10.0, 35.5], abs=1e-9)
        assert a_xs == pytest.approx([45.5 + ba + 10.0, 45.5 + ba + 35.5], abs=1e-9)

    def test_grid_1x1_дає_2_отвори_у_центрах(self) -> None:
        result = unfold_corner_angle(
            self._params(hole_rows=1, hole_cols=1, hole_margin_mm=10.0), k_factor=0.4
        )
        assert len(result.holes) == 2
        # x: центр сегмента B = 22.75; центр A = 45.5+BA + 22.75
        ba = result.bend_allowance_mm
        xs = sorted(h.x_mm for h in result.holes)
        assert xs[0] == pytest.approx(45.5 / 2, abs=1e-9)
        assert xs[1] == pytest.approx(45.5 + ba + 45.5 / 2, abs=1e-9)

    def test_детермінізм(self) -> None:
        params = self._params()
        a = unfold_corner_angle(params, k_factor=0.4)
        b = unfold_corner_angle(params, k_factor=0.4)
        assert a == b


class TestUnfoldWallShelf:
    def _params(self, **overrides: float | int) -> WallShelfBuildParameters:
        defaults: dict[str, float | int] = {
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
        return WallShelfBuildParameters(**defaults)  # type: ignore[arg-type]

    def test_розгортка_з_lip_80_150_20_t2_r25(self) -> None:
        """L = (80 − 2 − 2.5) + BA + (150 − 2·(2+2.5)) + BA + (20 − 2 − 2.5)
        = 75.5 + BA + 141 + BA + 15.5.
        """
        result = unfold_wall_shelf(self._params(), k_factor=0.4)
        assert isinstance(result, UnfoldedWallShelf)
        ba = (math.pi / 2) * 3.3
        expected = 75.5 + ba + 141.0 + ba + 15.5
        assert result.length_mm == pytest.approx(expected, abs=1e-9)
        assert len(result.bend_positions_mm) == 2
        # bend1 = flat_back + BA/2 = 75.5 + BA/2
        assert result.bend_positions_mm[0] == pytest.approx(75.5 + ba / 2, abs=1e-9)
        # bend2 = flat_back + BA + flat_shelf + BA/2 = 75.5 + BA + 141 + BA/2
        assert result.bend_positions_mm[1] == pytest.approx(75.5 + ba + 141.0 + ba / 2, abs=1e-9)

    def test_без_lip_тільки_1_bend(self) -> None:
        """front_lip_mm=0 → пропускаємо 2-й сегмент і другий гиб."""
        result = unfold_wall_shelf(self._params(front_lip_mm=0.0), k_factor=0.4)
        ba = (math.pi / 2) * 3.3
        # flat_shelf без lip = sd - (t+r) (один кут) = 150 - 4.5 = 145.5
        expected = 75.5 + ba + 145.5
        assert result.length_mm == pytest.approx(expected, abs=1e-9)
        assert len(result.bend_positions_mm) == 1

    def test_mount_holes_2x2_дає_4_отвори_на_back(self) -> None:
        result = unfold_wall_shelf(self._params(), k_factor=0.4)
        assert len(result.holes) == 4
        # Усі отвори у back-секції (x ∈ [0, flat_back=75.5]).
        for h in result.holes:
            assert 0 <= h.x_mm <= 75.5
            assert h.diameter_mm == 6.0

    def test_mount_holes_3x3_дає_9_отворів(self) -> None:
        result = unfold_wall_shelf(self._params(mount_hole_rows=3, mount_hole_cols=3), k_factor=0.4)
        assert len(result.holes) == 9

    def test_закороткий_back_кидає(self) -> None:
        params = WallShelfBuildParameters.model_construct(
            back_height_mm=10.0,
            shelf_depth_mm=150.0,
            front_lip_mm=20.0,
            bend_radius_mm=5.0,
            bend_angle_deg=90,
            width_mm=300.0,
            thickness_mm=8.0,
            mount_hole_diameter_mm=6.0,
            mount_hole_rows=2,
            mount_hole_cols=2,
            mount_hole_margin_mm=15.0,
        )
        with pytest.raises(ValueError, match="too short"):
            unfold_wall_shelf(params, k_factor=0.4)

    def test_детермінізм(self) -> None:
        params = self._params()
        a = unfold_wall_shelf(params, k_factor=0.4)
        b = unfold_wall_shelf(params, k_factor=0.4)
        assert a == b
