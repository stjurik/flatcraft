"""DXF-експорт: structural-snapshot + байт-у-байт регресія."""

from pathlib import Path
from typing import Any

import pytest
from ezdxf import readfile  # type: ignore[attr-defined]

from flatcraft_cad.export.dxf import DXF_LAYERS, export_l_bracket_dxf
from flatcraft_cad.templates.l_bracket import LBracketBuildParameters
from flatcraft_cad.unfold import unfold_l_bracket

SNAPSHOTS_DIR = Path(__file__).parent / "snapshots" / "dxf"


def _params(**overrides: Any) -> LBracketBuildParameters:
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


class TestStructural:
    """Перевіряємо, що saved DXF дійсно містить очікувані entities на
    очікуваних шарах — не залежить від байтового layout."""

    def test_має_всі_очікувані_шари(self, tmp_path: Path) -> None:
        params = _params()
        unf = unfold_l_bracket(params, k_factor=0.4)
        out = export_l_bracket_dxf(unf, tmp_path / "l.dxf", bend_radius_mm=params.bend_radius_mm)
        doc = readfile(out)
        layer_names = {layer.dxf.name for layer in doc.layers}
        for expected, _color in DXF_LAYERS:
            assert expected in layer_names, f"Missing layer {expected}"

    def test_laser_cut_прямокутник_правильних_розмірів(self, tmp_path: Path) -> None:
        params = _params(leg_a_mm=40, leg_b_mm=80, width_mm=200)
        unf = unfold_l_bracket(params, k_factor=0.4)
        out = export_l_bracket_dxf(unf, tmp_path / "l.dxf", bend_radius_mm=params.bend_radius_mm)
        doc = readfile(out)
        polys = list(doc.modelspace().query("LWPOLYLINE[layer=='LASER_CUT']"))
        assert len(polys) == 1
        pts = list(polys[0].get_points("xy"))
        assert pts[0] == pytest.approx((0.0, 0.0))
        assert pts[1] == pytest.approx((unf.length_mm, 0.0))
        assert pts[2] == pytest.approx((unf.length_mm, unf.width_mm))
        assert pts[3] == pytest.approx((0.0, unf.width_mm))

    def test_bend_line_на_позиції_розрахунку(self, tmp_path: Path) -> None:
        params = _params()
        unf = unfold_l_bracket(params, k_factor=0.4)
        out = export_l_bracket_dxf(unf, tmp_path / "l.dxf", bend_radius_mm=params.bend_radius_mm)
        doc = readfile(out)
        lines = list(doc.modelspace().query("LINE[layer=='BEND_LINES']"))
        assert len(lines) == 1
        line = lines[0]
        assert line.dxf.start.x == pytest.approx(unf.bend_position_mm)
        assert line.dxf.end.x == pytest.approx(unf.bend_position_mm)
        assert line.dxf.start.y == pytest.approx(0.0)
        assert line.dxf.end.y == pytest.approx(unf.width_mm)

    def test_bend_text_містить_кут_і_радіус(self, tmp_path: Path) -> None:
        params = _params()
        unf = unfold_l_bracket(params, k_factor=0.4)
        out = export_l_bracket_dxf(
            unf,
            tmp_path / "l.dxf",
            bend_radius_mm=params.bend_radius_mm,
            bend_angle_deg=90,
        )
        doc = readfile(out)
        texts = list(doc.modelspace().query("TEXT[layer=='BEND_TEXT']"))
        assert len(texts) == 1
        assert "90" in texts[0].dxf.text
        assert "2.5" in texts[0].dxf.text

    def test_кожен_шар_має_конфігурований_колір(self, tmp_path: Path) -> None:
        params = _params()
        unf = unfold_l_bracket(params, k_factor=0.4)
        out = export_l_bracket_dxf(unf, tmp_path / "l.dxf", bend_radius_mm=params.bend_radius_mm)
        doc = readfile(out)
        for name, expected_color in DXF_LAYERS:
            layer = doc.layers.get(name)
            assert layer.dxf.color == expected_color


class TestDeterminism:
    """Phase 1.8: однакові params → байт-у-байт однакові DXF."""

    def test_однаковий_вхід_однакові_байти(self, tmp_path: Path) -> None:
        params = _params()
        unf = unfold_l_bracket(params, k_factor=0.4)
        a = export_l_bracket_dxf(
            unf, tmp_path / "a.dxf", bend_radius_mm=params.bend_radius_mm
        ).read_bytes()
        b = export_l_bracket_dxf(
            unf, tmp_path / "b.dxf", bend_radius_mm=params.bend_radius_mm
        ).read_bytes()
        assert a == b

    def test_різний_вхід_різні_байти(self, tmp_path: Path) -> None:
        unf_small = unfold_l_bracket(_params(), k_factor=0.4)
        unf_big = unfold_l_bracket(_params(leg_a_mm=120), k_factor=0.4)
        a = export_l_bracket_dxf(unf_small, tmp_path / "a.dxf", bend_radius_mm=2.5).read_bytes()
        b = export_l_bracket_dxf(unf_big, tmp_path / "b.dxf", bend_radius_mm=2.5).read_bytes()
        assert a != b


class TestSnapshot:
    """Регресія: фіксований params → фіксований DXF-байт-output.

    Якщо тест падає — або змінилася формула розгортки/контур, або
    оновили ezdxf. У такому випадку:
      1. Перевірити що зміна геометрично коректна (через TestStructural).
      2. Оновити snapshot: `pytest --snapshot-update` (pytest-snapshot).
    """

    @pytest.mark.parametrize(
        ("name", "params_overrides"),
        [
            ("l_bracket_60x60_t2_r25", {}),
            (
                "l_bracket_40x80_t1.5_r2.5",
                {"leg_a_mm": 40, "leg_b_mm": 80, "thickness_mm": 1.5},
            ),
            (
                "l_bracket_120x80_t3_r4",
                {"leg_a_mm": 120, "leg_b_mm": 80, "thickness_mm": 3, "bend_radius_mm": 4},
            ),
        ],
    )
    def test_dxf_snapshot(
        self,
        snapshot: Any,
        tmp_path: Path,
        name: str,
        params_overrides: dict[str, float],
    ) -> None:
        params = _params(**params_overrides)
        unf = unfold_l_bracket(params, k_factor=0.4)
        out = export_l_bracket_dxf(
            unf, tmp_path / f"{name}.dxf", bend_radius_mm=params.bend_radius_mm
        )
        # Bytes (а не str) — щоб уникнути newline-нормалізації, бо ezdxf
        # пише \r\n, а _file_encode у pytest-snapshot забороняє \r у рядках.
        snapshot.snapshot_dir = SNAPSHOTS_DIR
        snapshot.assert_match(out.read_bytes(), f"{name}.dxf")
