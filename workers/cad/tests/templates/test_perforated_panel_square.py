"""Тести perforated_panel_square (Phase 3.0 PR 5, ADR-027 Рішення 6).

Перевіряємо: Pydantic парс, builder повертає Workplane, unfold обчислює
grid; DXF емітить LWPOLYLINE замість CIRCLE; PDF містить '□' замість 'Ø';
детермінізм байт.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from ezdxf import readfile  # type: ignore[attr-defined]
from pydantic import ValidationError
from pypdf import PdfReader

from flatcraft_cad.export.dxf import export_perforated_panel_square_dxf
from flatcraft_cad.export.pdf import export_perforated_panel_square_pdf
from flatcraft_cad.templates.perforated_panel_square import (
    PerforatedPanelSquareBuildParameters,
    build_perforated_panel_square,
)
from flatcraft_cad.unfold import unfold_perforated_panel_square

VALID = PerforatedPanelSquareBuildParameters(
    length_mm=200,
    width_mm=150,
    thickness_mm=1.5,
    hole_size_mm=8,
    pitch_x_mm=30,
    pitch_y_mm=30,
    margin_mm=15,
)


def test_pydantic_parse_accepts_valid_params() -> None:
    p = PerforatedPanelSquareBuildParameters.model_validate(
        {
            "length_mm": 200,
            "width_mm": 150,
            "thickness_mm": 1.5,
            "hole_size_mm": 8,
            "pitch_x_mm": 30,
            "pitch_y_mm": 30,
            "margin_mm": 15,
        }
    )
    assert p.hole_size_mm == 8
    assert p.length_mm == 200


def test_pydantic_rejects_invalid_hole_size() -> None:
    with pytest.raises(ValidationError):
        PerforatedPanelSquareBuildParameters(
            length_mm=200,
            width_mm=150,
            thickness_mm=1.5,
            hole_size_mm=999,  # за межами 3-30
            pitch_x_mm=30,
            pitch_y_mm=30,
            margin_mm=15,
        )


def test_builder_returns_workplane() -> None:
    wp = build_perforated_panel_square(VALID)
    # cadquery Workplane має метод val() для отримання solid'а
    assert wp is not None
    solid = wp.val()
    assert solid is not None


def test_unfold_produces_centered_grid() -> None:
    unfolded = unfold_perforated_panel_square(VALID)
    # 200мм - 2*15мм margin = 170мм. 170/30 = 5 → 6 cols.
    # 150мм - 2*15мм margin = 120мм. 120/30 = 4 → 5 rows.
    assert unfolded.grid_cols == 6
    assert unfolded.grid_rows == 5
    assert len(unfolded.holes) == 30
    # Усі holes мають shape='square'.
    for h in unfolded.holes:
        assert h.shape == "square"
        assert h.diameter_mm == 8  # side length


def test_dxf_emits_lwpolyline_per_hole_not_circle(tmp_path: Path) -> None:
    """ADR-027 Рішення 6 ключовий інваріант: square holes → LWPOLYLINE 4 vertices."""
    unfolded = unfold_perforated_panel_square(VALID)
    output = tmp_path / "out.dxf"
    export_perforated_panel_square_dxf(unfolded, output)

    doc = readfile(str(output))
    msp = doc.modelspace()
    polylines = [e for e in msp if e.dxftype() == "LWPOLYLINE"]
    circles = [e for e in msp if e.dxftype() == "CIRCLE"]
    # 1 outer perimeter LWPOLYLINE + 30 hole LWPOLYLINE = 31 total.
    assert len(polylines) == 31, f"Expected 31 LWPOLYLINE; got {len(polylines)}"
    # Нуль CIRCLE entities (square holes).
    assert len(circles) == 0, f"Expected 0 CIRCLE; got {len(circles)}"


def test_dxf_hole_lwpolylines_have_color_5_blue(tmp_path: Path) -> None:
    """ADR-024 інваріант: inner cuts color 5 (blue) для візуального розрізнення."""
    unfolded = unfold_perforated_panel_square(VALID)
    output = tmp_path / "out.dxf"
    export_perforated_panel_square_dxf(unfolded, output)

    doc = readfile(str(output))
    msp = doc.modelspace()
    polylines = [e for e in msp if e.dxftype() == "LWPOLYLINE"]
    # Outer perimeter — ByLayer (color 256). Holes — color 5.
    inner_cuts = [p for p in polylines if p.dxf.color == 5]
    outer = [p for p in polylines if p.dxf.color != 5]
    assert len(inner_cuts) == 30, f"Expected 30 color-5 polylines; got {len(inner_cuts)}"
    assert len(outer) == 1, f"Expected 1 ByLayer polyline (outer); got {len(outer)}"


def test_dxf_only_two_custom_layers(tmp_path: Path) -> None:
    """ADR-024 інваріант: рівно 2 виробничі шари (LASER_CUT + BEND_LINES).

    perforated_panel_square має BEND_LINES як empty layer (без entities) бо
    немає гибів. Custom-layers: 2.
    """
    unfolded = unfold_perforated_panel_square(VALID)
    output = tmp_path / "out.dxf"
    export_perforated_panel_square_dxf(unfolded, output)

    doc = readfile(str(output))
    # Custom layers — окрім '0' і 'Defpoints'.
    custom = [layer.dxf.name for layer in doc.layers if layer.dxf.name not in ("0", "Defpoints")]
    assert set(custom) == {"LASER_CUT", "BEND_LINES"}


def test_pdf_contains_square_glyph_not_diameter(tmp_path: Path) -> None:
    """ADR-027 Рішення 6: PDF callout '□' замість 'Ø' для square holes."""
    unfolded = unfold_perforated_panel_square(VALID)
    output = tmp_path / "out.pdf"
    export_perforated_panel_square_pdf(VALID, unfolded, output)

    reader = PdfReader(str(output))
    text = "".join(p.extract_text() or "" for p in reader.pages)
    assert "□" in text
    # 'Ø' не повинен з'являтись у цьому документі (тільки square holes).
    assert "Ø" not in text


def test_pdf_renders_square_holes_as_rects_not_circles(tmp_path: Path) -> None:
    """PR 8a regression-fix: PDF візуальний рендер квадратних отворів.

    ДО фіксу `_draw_unfold_generic` завжди викликав c.circle() — square holes
    на креслі виглядали як кола, попри текстовий callout '□'. Перевіряємо
    content stream: reportlab `c.rect()` → "re" op, `c.circle()` → curveto
    (~8 "c" op per circle). Очікуємо ≥ 30 "re" операторів (outer perimeter +
    30 holes у дефолтному grid VALID = 5×6 = 30; пара ще і у BOM таблицях).
    """
    unfolded = unfold_perforated_panel_square(VALID)
    output = tmp_path / "out.pdf"
    export_perforated_panel_square_pdf(VALID, unfolded, output)

    # Витягаємо content stream сторінки (decompressed pypdf'ом).
    reader = PdfReader(str(output))
    blob_parts: list[str] = []
    for page in reader.pages:
        contents = page.get_contents()
        if contents is None:
            continue
        data = contents.get_data()
        blob_parts.append(data.decode("latin-1", errors="ignore"))
    blob = "\n".join(blob_parts)
    # "re" — оператор rectangle; з'являється на кожен hole + outer perimeter.
    re_count = sum(1 for op in blob.split() if op == "re")
    # 30 holes + outer perimeter + кілька технічних (BOM/grid summary рамки)
    # → мінімум 30.
    assert re_count >= 30, f"Expected ≥30 're' (rect) ops in PDF; got {re_count}"


def test_dxf_byte_determinism(tmp_path: Path) -> None:
    """CLAUDE.md §2.4 інваріант: однаковий вхід → байт-у-байт identical DXF."""
    unfolded = unfold_perforated_panel_square(VALID)
    out1 = tmp_path / "a.dxf"
    out2 = tmp_path / "b.dxf"
    export_perforated_panel_square_dxf(unfolded, out1)
    export_perforated_panel_square_dxf(unfolded, out2)
    assert out1.read_bytes() == out2.read_bytes()


def test_pdf_byte_determinism(tmp_path: Path) -> None:
    """CLAUDE.md §2.4 інваріант: PDF теж байт-determinist."""
    unfolded = unfold_perforated_panel_square(VALID)
    out1 = tmp_path / "a.pdf"
    out2 = tmp_path / "b.pdf"
    export_perforated_panel_square_pdf(VALID, unfolded, out1)
    export_perforated_panel_square_pdf(VALID, unfolded, out2)
    assert out1.read_bytes() == out2.read_bytes()
