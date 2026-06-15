"""Тести політики Ø-виносок отворів: PDF-розміри (Phase 2.9.b F) + DXF
cut-кола на LASER_CUT (Hotfix 2.9.d / ADR-024 — у DXF без розмірів)."""

from __future__ import annotations

from pathlib import Path

from ezdxf import readfile  # type: ignore[attr-defined]

from flatcraft_cad.export.dxf import (
    export_corner_angle_dxf,
    export_perforated_panel_dxf,
)
from flatcraft_cad.export.layout.hole_dims import (
    HOLE_DIM_CAP,
    should_dim_individual_holes,
)
from flatcraft_cad.templates.corner_angle import CornerAngleBuildParameters
from flatcraft_cad.templates.perforated_panel import PerforatedPanelBuildParameters
from flatcraft_cad.unfold import unfold_corner_angle, unfold_perforated_panel


def _corner_params(**over: object) -> CornerAngleBuildParameters:
    base: dict[str, object] = {
        "leg_a_mm": 100,
        "leg_b_mm": 70,
        "width_mm": 120,
        "thickness_mm": 2,
        "bend_radius_mm": 2.5,
        "hole_diameter_mm": 8,
        "hole_rows": 2,
        "hole_cols": 2,
        "hole_margin_mm": 15,
    }
    base.update(over)
    return CornerAngleBuildParameters(**base)  # type: ignore[arg-type]


class TestShouldDimIndividualHoles:
    def test_небагато_отворів_дімимо_кожен(self) -> None:
        assert should_dim_individual_holes(4) is True

    def test_рівно_cap_включно(self) -> None:
        assert should_dim_individual_holes(HOLE_DIM_CAP) is True

    def test_понад_cap_не_дімимо(self) -> None:
        assert should_dim_individual_holes(HOLE_DIM_CAP + 1) is False

    def test_нуль_отворів(self) -> None:
        assert should_dim_individual_holes(0) is True

    def test_кастомний_cap(self) -> None:
        assert should_dim_individual_holes(5, cap=3) is False
        assert should_dim_individual_holes(3, cap=3) is True


class TestDxfHoleCuts:
    """ADR-024: у DXF отвори — CIRCLE на LASER_CUT (color 5), БЕЗ Ø-розмірів.

    Діаметричні виноски лишаються тільки у PDF (TestPdfHoleDims) — у DXF це
    CAM-noise. Раніше отвори дімилися на DIM_HOLES і жили на INNER_CUTS —
    обидва шари прибрано."""

    def test_corner_angle_отвори_кола_на_laser_cut(self, tmp_path: Path) -> None:
        params = _corner_params()
        unf = unfold_corner_angle(params, 0.4)
        out = export_corner_angle_dxf(unf, tmp_path / "c.dxf", bend_radius_mm=params.bend_radius_mm)
        doc = readfile(out)
        msp = doc.modelspace()
        circles = list(msp.query("CIRCLE"))
        assert len(circles) == len(unf.holes)
        assert len(unf.holes) > 0
        for circ in circles:
            assert circ.dxf.layer == "LASER_CUT"
            assert int(circ.dxf.color) == 5
        # Жодних розмірів/допоміжних шарів.
        assert not list(msp.query("DIMENSION"))
        assert not doc.layers.has_entry("DIM_HOLES")
        assert not doc.layers.has_entry("INNER_CUTS")

    def test_perforated_багато_отворів_без_розмірів(self, tmp_path: Path) -> None:
        params = PerforatedPanelBuildParameters(
            length_mm=400,
            width_mm=300,
            thickness_mm=2,
            hole_diameter_mm=8,
            pitch_x_mm=30,
            pitch_y_mm=30,
            margin_mm=20,
        )
        unf = unfold_perforated_panel(params)
        assert len(unf.holes) > HOLE_DIM_CAP  # справді багато
        out = export_perforated_panel_dxf(unf, tmp_path / "p.dxf")
        doc = readfile(out)
        msp = doc.modelspace()
        circles = list(msp.query("CIRCLE"))
        # Усі отвори — повноцінні кола на LASER_CUT (CAM ріже кожен), без анотацій.
        assert len(circles) == len(unf.holes)
        assert all(c.dxf.layer == "LASER_CUT" and int(c.dxf.color) == 5 for c in circles)
        assert not list(msp.query("DIMENSION"))
        assert not list(msp.query("TEXT"))

    def test_dim_детермінізм_однакові_байти(self, tmp_path: Path) -> None:
        params = _corner_params()
        unf = unfold_corner_angle(params, 0.4)
        a = export_corner_angle_dxf(unf, tmp_path / "a.dxf", bend_radius_mm=2.5).read_bytes()
        b = export_corner_angle_dxf(unf, tmp_path / "b.dxf", bend_radius_mm=2.5).read_bytes()
        assert a == b


class TestPdfHoleDims:
    """Ø-виноски у PDF: на кожен отвір (corner) або «×N отворів» (perfo)."""

    def test_corner_angle_pdf_містить_діаметр(self, tmp_path: Path) -> None:
        from pypdf import PdfReader

        from flatcraft_cad.export.pdf import export_corner_angle_pdf

        params = _corner_params()
        unf = unfold_corner_angle(params, 0.4)
        out = export_corner_angle_pdf(params, unf, tmp_path / "c.pdf")
        text = PdfReader(str(out)).pages[0].extract_text() or ""
        assert "Ø8" in text

    def test_perforated_pdf_містить_анотацію_кількості(self, tmp_path: Path) -> None:
        from pypdf import PdfReader

        from flatcraft_cad.export.pdf import export_perforated_panel_pdf

        params = PerforatedPanelBuildParameters(
            length_mm=400,
            width_mm=300,
            thickness_mm=2,
            hole_diameter_mm=8,
            pitch_x_mm=30,
            pitch_y_mm=30,
            margin_mm=20,
        )
        unf = unfold_perforated_panel(params)
        out = export_perforated_panel_pdf(params, unf, tmp_path / "p.pdf")
        text = PdfReader(str(out)).pages[0].extract_text() or ""
        assert "отворів Ø8" in text
