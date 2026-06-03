"""Напрям згину у DXF/PDF (Hotfix 2.10.e D).

Перевіряємо, що напрям (UP/DOWN) доходить до DXF bend-text і що дефолт — DOWN.
"""

from __future__ import annotations

from pathlib import Path

from pypdf import PdfReader

from flatcraft_cad.export.dxf import export_l_bracket_dxf, export_z_bracket_dxf
from flatcraft_cad.export.pdf import export_l_bracket_pdf, export_z_bracket_pdf
from flatcraft_cad.templates.l_bracket import LBracketBuildParameters
from flatcraft_cad.templates.z_bracket import ZBracketBuildParameters
from flatcraft_cad.unfold import UnfoldedLBracket, unfold_l_bracket, unfold_z_bracket


def _l_unfold() -> UnfoldedLBracket:
    params = LBracketBuildParameters.model_validate(
        {
            "leg_a_mm": 60,
            "leg_b_mm": 60,
            "bend_radius_mm": 2.5,
            "width_mm": 100,
            "thickness_mm": 2.0,
        }
    )
    return unfold_l_bracket(params, k_factor=0.4)


def test_l_bracket_dxf_дефолт_down(tmp_path: Path) -> None:
    out = export_l_bracket_dxf(_l_unfold(), tmp_path / "l.dxf", bend_radius_mm=2.5)
    text = out.read_text(encoding="utf-8")
    assert "BEND 90° DOWN R2.5 #1" in text
    # Жодного UP саме у bend-text (підрядок "UP" окремо є у DXF "GROUP" об'єктах).
    assert "UP R2.5" not in text


def test_l_bracket_dxf_up(tmp_path: Path) -> None:
    out = export_l_bracket_dxf(
        _l_unfold(),
        tmp_path / "l.dxf",
        bend_radius_mm=2.5,
        bend_direction="up",
    )
    text = out.read_text(encoding="utf-8")
    assert "BEND 90° UP R2.5 #1" in text


def test_z_bracket_dxf_mixed_directions(tmp_path: Path) -> None:
    params = ZBracketBuildParameters(
        top_flange_mm=60,
        bottom_flange_mm=60,
        offset_mm=40,
        bend_radius_mm=2.5,
        width_mm=100,
        thickness_mm=2.0,
    )
    unf = unfold_z_bracket(params, k_factor=0.4)
    out = export_z_bracket_dxf(
        unf, tmp_path / "z.dxf", bend_radius_mm=2.5, bend_directions=("down", "up")
    )
    text = out.read_text(encoding="utf-8")
    assert "DOWN R2.5 #1" in text
    assert "UP R2.5 #2" in text


def _l_params(direction: str) -> LBracketBuildParameters:
    return LBracketBuildParameters.model_validate(
        {
            "leg_a_mm": 60,
            "leg_b_mm": 60,
            "bend_radius_mm": 2.5,
            "width_mm": 100,
            "thickness_mm": 2.0,
            "bend_direction": direction,
        }
    )


def test_l_bracket_pdf_напрям_текстом_down(tmp_path: Path) -> None:
    """PDF рендерить напрям текстом DOWN/UP, не стрілкою ↓/↑."""
    params = _l_params("down")
    unf = unfold_l_bracket(params, k_factor=0.4)
    pdf = export_l_bracket_pdf(params, unf, tmp_path / "l.pdf")
    text = PdfReader(str(pdf)).pages[0].extract_text() or ""
    assert "DOWN" in text
    assert "↓" not in text
    assert "↑" not in text


def test_l_bracket_pdf_напрям_текстом_up(tmp_path: Path) -> None:
    params = _l_params("up")
    unf = unfold_l_bracket(params, k_factor=0.4)
    pdf = export_l_bracket_pdf(params, unf, tmp_path / "l.pdf")
    text = PdfReader(str(pdf)).pages[0].extract_text() or ""
    assert "UP" in text
    assert "↑" not in text


def test_z_bracket_pdf_дефолт_down_up(tmp_path: Path) -> None:
    """Дефолтний Z-кронштейн: гиб 1 = DOWN, гиб 2 = UP (геометрично коректно)."""
    params = ZBracketBuildParameters.model_validate(
        {
            "top_flange_mm": 60,
            "bottom_flange_mm": 60,
            "offset_mm": 40,
            "bend_radius_mm": 2.5,
            "width_mm": 100,
            "thickness_mm": 2.0,
        }
    )
    assert tuple(b.direction for b in params.bends) == ("down", "up")
    unf = unfold_z_bracket(params, k_factor=0.4)
    pdf = export_z_bracket_pdf(params, unf, tmp_path / "z.pdf")
    text = PdfReader(str(pdf)).pages[0].extract_text() or ""
    assert "DOWN" in text
    assert "UP" in text
