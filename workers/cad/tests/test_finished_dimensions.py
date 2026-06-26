"""Тести pure-функції габаритів готового (зігнутого) виробу — Phase 2.9.b Block C.

Конвенція осей (єдина для всіх шаблонів, див. dimensions.py docstring):
  X × Y — bounding box силуету профілю (поперечний переріз зігнутої деталі),
  Z     — довжина лінії гибу / extrude (= width_mm) для гнутих шаблонів;
          для плоскої перфо-панелі Z = товщина.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from flatcraft_cad.export.dimensions import (
    FinishedDimensions,
    compute_finished_dimensions,
    format_dimensions,
)
from flatcraft_cad.templates.corner_angle import CornerAngleBuildParameters
from flatcraft_cad.templates.l_bracket import LBracketBuildParameters
from flatcraft_cad.templates.perforated_panel import PerforatedPanelBuildParameters
from flatcraft_cad.templates.wall_shelf import WallShelfBuildParameters
from flatcraft_cad.templates.z_bracket import ZBracketBuildParameters


def _l(**over: float) -> LBracketBuildParameters:
    base: dict[str, float] = {
        "leg_a_mm": 100,
        "leg_b_mm": 80,
        "width_mm": 100,
        "thickness_mm": 2,
        "bend_radius_mm": 2.5,
    }
    base.update(over)
    return LBracketBuildParameters(**base)  # type: ignore[arg-type]


class TestLBracket:
    def test_дефолтні_габарити(self) -> None:
        d = compute_finished_dimensions("l_bracket", _l())
        assert (d.x_mm, d.y_mm, d.z_mm) == (100, 80, 100)

    def test_інші_довжини_полиць(self) -> None:
        d = compute_finished_dimensions("l_bracket", _l(leg_a_mm=120, leg_b_mm=40, width_mm=250))
        assert (d.x_mm, d.y_mm, d.z_mm) == (120, 40, 250)


class TestCornerAngle:
    def _c(self, **over: float) -> CornerAngleBuildParameters:
        base: dict[str, float] = {
            "leg_a_mm": 100,
            "leg_b_mm": 70,
            "width_mm": 120,
            "thickness_mm": 2,
            "bend_radius_mm": 2.5,
            "hole_diameter_mm": 6,
            "hole_rows": 2,
            "hole_cols": 2,
            "hole_margin_mm": 15,
        }
        base.update(over)
        return CornerAngleBuildParameters(**base)  # type: ignore[arg-type]

    def test_ідентичний_l_bracket_формулі(self) -> None:
        d = compute_finished_dimensions("corner_angle", self._c())
        assert (d.x_mm, d.y_mm, d.z_mm) == (100, 70, 120)

    def test_варіант_розмірів(self) -> None:
        d = compute_finished_dimensions("corner_angle", self._c(leg_a_mm=60, leg_b_mm=60))
        assert (d.x_mm, d.y_mm) == (60, 60)


class TestZBracket:
    def _z(self, **over: float) -> ZBracketBuildParameters:
        base: dict[str, object] = {
            "top_flange_mm": 50,
            "bottom_flange_mm": 60,
            "offset_mm": 40,
            "width_mm": 100,
            "thickness_mm": 2,
            "bend_radius_mm": 2.5,
            "bends": ({"direction": "down"}, {"direction": "up"}),
        }
        base.update(over)
        return ZBracketBuildParameters(**base)  # type: ignore[arg-type]

    def test_x_сума_полиць_y_offset_z_width(self) -> None:
        d = compute_finished_dimensions("z_bracket", self._z())
        assert d.x_mm == 110  # 50 + 60
        assert d.y_mm == 40
        assert d.z_mm == 100

    def test_більший_offset(self) -> None:
        d = compute_finished_dimensions("z_bracket", self._z(offset_mm=120))
        assert d.y_mm == 120


class TestWallShelf:
    def _w(self, **over: float) -> WallShelfBuildParameters:
        base: dict[str, object] = {
            "back_height_mm": 120,
            "shelf_depth_mm": 200,
            "front_lip_mm": 30,
            "width_mm": 300,
            "thickness_mm": 2,
            "bend_radius_mm": 2.5,
            "bends": ({"direction": "down"}, {"direction": "down"}),
            "mount_hole_diameter_mm": 6,
            "mount_hole_rows": 2,
            "mount_hole_cols": 2,
            "mount_hole_margin_mm": 15,
        }
        base.update(over)
        return WallShelfBuildParameters(**base)  # type: ignore[arg-type]

    def test_back_вище_за_lip(self) -> None:
        d = compute_finished_dimensions("wall_shelf", self._w())
        assert d.x_mm == 200  # shelf_depth
        assert d.y_mm == 120  # max(back=120, lip=30)
        assert d.z_mm == 300  # width

    def test_lip_вищий_за_back_визначає_y(self) -> None:
        d = compute_finished_dimensions("wall_shelf", self._w(back_height_mm=40, front_lip_mm=80))
        assert d.y_mm == 80

    def test_без_lip(self) -> None:
        d = compute_finished_dimensions("wall_shelf", self._w(front_lip_mm=0))
        assert d.y_mm == 120


class TestPerforatedPanel:
    def _p(self, **over: float | str) -> PerforatedPanelBuildParameters:
        base: dict[str, float | str] = {
            "length_mm": 400,
            "width_mm": 300,
            "thickness_mm": 2,
            "hole_shape": "square",
            "hole_size_mm": 8,
            "pitch_x_mm": 30,
            "pitch_y_mm": 30,
            "margin_mm": 20,
            "rib_height_mm": 30,
        }
        base.update(over)
        return PerforatedPanelBuildParameters.model_validate(base)

    def test_лоток_z_товщина_плюс_ребро(self) -> None:
        # Ребриста панель (ADR-031): X×Y = площина, Z = товщина + висота ребра.
        d = compute_finished_dimensions("perforated_panel", self._p())
        assert (d.x_mm, d.y_mm, d.z_mm) == (400, 300, 2 + 30)

    def test_тонкий_лист(self) -> None:
        d = compute_finished_dimensions("perforated_panel", self._p(thickness_mm=0.5))
        assert d.z_mm == 0.5 + 30


class TestPdfHeaderIntegration:
    """Інтеграція: рядок «Габарити готового виробу» присутній у PDF усіх 5 шаблонів.

    Асерт лише на лейбл (Cyrillic екстрактується pypdf) — символ × не
    екстрактується, тож точні числа перевіряють unit-тести format/compute.
    """

    def _all_templates(self, tmp_path: Path) -> list[tuple[str, Path]]:
        from flatcraft_cad.export.pdf import (
            export_corner_angle_pdf,
            export_l_bracket_pdf,
            export_perforated_panel_pdf,
            export_wall_shelf_pdf,
            export_z_bracket_pdf,
        )
        from flatcraft_cad.unfold import (
            unfold_corner_angle,
            unfold_l_bracket,
            unfold_perforated_panel,
            unfold_wall_shelf,
            unfold_z_bracket,
        )

        out: list[tuple[str, Path]] = []

        lp = _l()
        out.append(
            ("l_bracket", export_l_bracket_pdf(lp, unfold_l_bracket(lp, 0.4), tmp_path / "l.pdf"))
        )

        zp = TestZBracket()._z()
        out.append(
            ("z_bracket", export_z_bracket_pdf(zp, unfold_z_bracket(zp, 0.4), tmp_path / "z.pdf"))
        )

        cp = TestCornerAngle()._c()
        out.append(
            (
                "corner_angle",
                export_corner_angle_pdf(cp, unfold_corner_angle(cp, 0.4), tmp_path / "c.pdf"),
            )
        )

        wp = TestWallShelf()._w()
        out.append(
            (
                "wall_shelf",
                export_wall_shelf_pdf(wp, unfold_wall_shelf(wp, 0.4), tmp_path / "w.pdf"),
            )
        )

        pp = TestPerforatedPanel()._p()
        out.append(
            (
                "perforated_panel",
                export_perforated_panel_pdf(pp, unfold_perforated_panel(pp), tmp_path / "p.pdf"),
            )
        )
        return out

    def test_header_рядок_у_всіх_шаблонах(self, tmp_path: Path) -> None:
        from pypdf import PdfReader

        for slug, path in self._all_templates(tmp_path):
            text = PdfReader(str(path)).pages[0].extract_text() or ""
            assert "Габарити готового виробу" in text, f"немає рядка габаритів у {slug}"


class TestErrors:
    def test_невідомий_slug_кидає(self) -> None:
        with pytest.raises(ValueError, match="невідом|unknown|slug"):
            compute_finished_dimensions("nonexistent", _l())


class TestFormatting:
    def test_цілі_без_trailing_zeros(self) -> None:
        s = format_dimensions(FinishedDimensions(x_mm=100, y_mm=80, z_mm=2))
        assert s == "100 × 80 × 2 мм"

    def test_округлення_до_0_1(self) -> None:
        s = format_dimensions(FinishedDimensions(x_mm=176.184, y_mm=80.0, z_mm=2.5))
        assert s == "176.2 × 80 × 2.5 мм"

    def test_дробове_без_зайвого_нуля(self) -> None:
        s = format_dimensions(FinishedDimensions(x_mm=1.5, y_mm=2.0, z_mm=3.25))
        # 3.25 → 3.2 (round to 0.1)
        assert s == "1.5 × 2 × 3.2 мм"
