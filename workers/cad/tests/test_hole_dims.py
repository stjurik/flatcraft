"""Тести політики розмірних виносок отворів + DXF DIM_HOLES (Phase 2.9.b F)."""

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


class TestDxfHoleDims:
    def test_corner_angle_dim_на_кожен_отвір(self, tmp_path: Path) -> None:
        params = _corner_params()
        unf = unfold_corner_angle(params, 0.4)
        out = export_corner_angle_dxf(
            unf, tmp_path / "c.dxf", bend_radius_mm=params.bend_radius_mm
        )
        doc = readfile(out)
        msp = doc.modelspace()
        assert doc.layers.has_entry("DIM_HOLES")
        dims = list(msp.query("DIMENSION[layer=='DIM_HOLES']"))
        # ≤ cap отворів → dim на кожен.
        assert len(dims) == len(unf.holes)
        assert len(unf.holes) > 0

    def test_perforated_багато_отворів_один_dim_плюс_текст(self, tmp_path: Path) -> None:
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
        dims = list(msp.query("DIMENSION[layer=='DIM_HOLES']"))
        assert len(dims) == 1  # лише один зразковий розмір
        texts = [t.dxf.text for t in msp.query("TEXT[layer=='DIM_HOLES']")]
        assert any("отвор" in t for t in texts)  # анотація «×N отворів»

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
