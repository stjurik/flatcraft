"""Тести уніфікованого perforated_panel (ADR-031): ребриста монтажна панель з
параметром форми отвору (circle|square).

Перевіряємо: Pydantic парс, builder (лоток, ребра вниз), unfold (cross-grid),
DXF (square→LWPOLYLINE, circle→CIRCLE; установочні Ø5.5→CIRCLE), PDF (глиф
□/Ø), детермінізм байт, ребра/кутові отвори/R5, валідація гибу+профілю.
"""

from __future__ import annotations

from pathlib import Path
from typing import cast

import cadquery as cq
import pytest
from ezdxf import readfile  # type: ignore[attr-defined]
from ezdxf.entities import LWPolyline  # type: ignore[attr-defined]
from pydantic import ValidationError
from pypdf import PdfReader

from flatcraft_cad.export.dxf import export_perforated_panel_dxf
from flatcraft_cad.export.pdf import export_perforated_panel_pdf
from flatcraft_cad.templates.perforated_panel import (
    PerforatedPanelBuildParameters,
    PerforatedPanelTemplate,
    build_perforated_panel,
)
from flatcraft_cad.unfold import unfold_perforated_panel

VALID = PerforatedPanelBuildParameters(
    length_mm=200,
    width_mm=150,
    thickness_mm=1.5,
    hole_shape="square",
    hole_size_mm=8,
    pitch_x_mm=30,
    pitch_y_mm=30,
    margin_mm=15,
    rib_height_mm=30,
)

VALID_CIRCLE = VALID.model_copy(update={"hole_shape": "circle"})


def test_pydantic_parse_accepts_valid_params() -> None:
    p = PerforatedPanelBuildParameters.model_validate(
        {
            "length_mm": 200,
            "width_mm": 150,
            "thickness_mm": 1.5,
            "hole_size_mm": 8,
            "pitch_x_mm": 30,
            "pitch_y_mm": 30,
            "margin_mm": 15,
            "rib_height_mm": 30,
        }
    )
    assert p.hole_size_mm == 8
    assert p.length_mm == 200
    assert p.rib_height_mm == 30
    # Дефолти ADR-030/031.
    assert p.hole_shape == "square"
    assert p.rib_corner_radius_mm == 5.0
    assert p.bend_radius_mm == 2.5
    assert p.corner_hole_inset_mm == 12.0


def test_pydantic_accepts_circle_hole_shape() -> None:
    p = VALID.model_copy(update={"hole_shape": "circle"})
    assert p.hole_shape == "circle"


def test_pydantic_rejects_invalid_hole_size() -> None:
    with pytest.raises(ValidationError):
        PerforatedPanelBuildParameters(
            length_mm=200,
            width_mm=150,
            thickness_mm=1.5,
            hole_size_mm=999,  # за межами 3-30
            pitch_x_mm=30,
            pitch_y_mm=30,
            margin_mm=15,
            rib_height_mm=30,
        )


def test_builder_returns_workplane_tray_with_ribs_down() -> None:
    wp = build_perforated_panel(VALID)
    obj = wp.val()
    assert isinstance(obj, cq.Shape)
    bb = obj.BoundingBox()
    # Площина z ∈ [0, t]; ребра вниз → zmin = -rib_height (ADR-031).
    assert bb.zmin == pytest.approx(-VALID.rib_height_mm, abs=1e-6)
    assert bb.zmax == pytest.approx(VALID.thickness_mm, abs=1e-6)


def test_unfold_produces_centered_grid() -> None:
    unfolded = unfold_perforated_panel(VALID)
    # 200мм - 2*15мм margin = 170мм. 170/30 = 5 → 6 cols.
    # 150мм - 2*15мм margin = 120мм. 120/30 = 4 → 5 rows.
    assert unfolded.grid_cols == 6
    assert unfolded.grid_rows == 5
    assert len(unfolded.holes) == 30
    for h in unfolded.holes:
        assert h.shape == "square"
        assert h.diameter_mm == 8  # side length


def test_unfold_circle_holes_carry_circle_shape() -> None:
    unfolded = unfold_perforated_panel(VALID_CIRCLE)
    assert len(unfolded.holes) == 30
    for h in unfolded.holes:
        assert h.shape == "circle"


def test_dxf_emits_square_perf_lwpolyline_and_corner_circles(tmp_path: Path) -> None:
    """ADR-030: перфорація → square LWPOLYLINE; установочні Ø5.5 → CIRCLE."""
    unfolded = unfold_perforated_panel(VALID)
    output = tmp_path / "out.dxf"
    export_perforated_panel_dxf(unfolded, output)

    doc = readfile(str(output))
    msp = doc.modelspace()
    polylines = [e for e in msp if e.dxftype() == "LWPOLYLINE"]
    circles = [e for e in msp if e.dxftype() == "CIRCLE"]
    # 1 cross-outline + N square-perf LWPOLYLINE (== len(holes)).
    assert len(polylines) == 1 + len(unfolded.holes)
    # Рівно 4 CIRCLE — кутові установочні отвори Ø5.5.
    assert len(circles) == 4, f"Expected 4 corner CIRCLE; got {len(circles)}"


def test_dxf_circle_perforation_emits_circles(tmp_path: Path) -> None:
    """ADR-031: hole_shape='circle' → перфорація CIRCLE (не LWPOLYLINE)."""
    unfolded = unfold_perforated_panel(VALID_CIRCLE)
    output = tmp_path / "out.dxf"
    export_perforated_panel_dxf(unfolded, output)

    doc = readfile(str(output))
    msp = doc.modelspace()
    polylines = [e for e in msp if e.dxftype() == "LWPOLYLINE"]
    circles = [e for e in msp if e.dxftype() == "CIRCLE"]
    # Лише cross-outline LWPOLYLINE; перфо + кутові → CIRCLE.
    assert len(polylines) == 1
    assert len(circles) == len(unfolded.holes) + 4


def test_dxf_hole_lwpolylines_have_color_5_blue(tmp_path: Path) -> None:
    """ADR-024 інваріант: inner cuts color 5 (blue) для візуального розрізнення."""
    unfolded = unfold_perforated_panel(VALID)
    output = tmp_path / "out.dxf"
    export_perforated_panel_dxf(unfolded, output)

    doc = readfile(str(output))
    msp = doc.modelspace()
    polylines = [e for e in msp if e.dxftype() == "LWPOLYLINE"]
    inner_cuts = [p for p in polylines if p.dxf.color == 5]
    outer = [p for p in polylines if p.dxf.color != 5]
    assert len(inner_cuts) == len(unfolded.holes)
    assert len(outer) == 1, f"Expected 1 ByLayer polyline (outer); got {len(outer)}"
    corner_circles = [e for e in msp if e.dxftype() == "CIRCLE"]
    assert all(cc.dxf.color == 5 for cc in corner_circles)


def test_dxf_only_two_custom_layers(tmp_path: Path) -> None:
    """ADR-024 інваріант: рівно 2 виробничі шари (LASER_CUT + BEND_LINES)."""
    unfolded = unfold_perforated_panel(VALID)
    output = tmp_path / "out.dxf"
    export_perforated_panel_dxf(unfolded, output)

    doc = readfile(str(output))
    custom = [layer.dxf.name for layer in doc.layers if layer.dxf.name not in ("0", "Defpoints")]
    assert set(custom) == {"LASER_CUT", "BEND_LINES"}


def test_pdf_contains_square_glyph_for_perforation(tmp_path: Path) -> None:
    """Квадратна перфорація позначається '□'; установочні отвори — 'Ø5.5'."""
    unfolded = unfold_perforated_panel(VALID)
    output = tmp_path / "out.pdf"
    export_perforated_panel_pdf(VALID, unfolded, output)

    reader = PdfReader(str(output))
    text = "".join(p.extract_text() or "" for p in reader.pages)
    assert "□" in text
    assert "Ø5.5" in text


def test_pdf_circle_uses_diameter_glyph(tmp_path: Path) -> None:
    """ADR-031: hole_shape='circle' → перфо-глиф 'Ø' у заголовку/таблиці."""
    unfolded = unfold_perforated_panel(VALID_CIRCLE)
    output = tmp_path / "out.pdf"
    export_perforated_panel_pdf(VALID_CIRCLE, unfolded, output)

    reader = PdfReader(str(output))
    text = "".join(p.extract_text() or "" for p in reader.pages)
    assert "Розмір отвору Ø" in text


def test_pdf_contains_unified_dimensions_table(tmp_path: Path) -> None:
    """Уніфікована таблиця «Розміри» з ребро/гиб/кріпильними рядками."""
    unfolded = unfold_perforated_panel(VALID)
    output = tmp_path / "out.pdf"
    export_perforated_panel_pdf(VALID, unfolded, output)

    reader = PdfReader(str(output))
    text = "".join(p.extract_text() or "" for p in reader.pages)
    assert "Розміри" in text
    assert "Розмір отвору" in text
    assert "Ребро h" in text
    assert "Кріпильні" in text
    assert "Заготовка" in text


def test_pdf_renders_square_holes_as_rects_not_circles(tmp_path: Path) -> None:
    """Квадратні отвори рендеряться як rect (re-оператори), не кола."""
    unfolded = unfold_perforated_panel(VALID)
    output = tmp_path / "out.pdf"
    export_perforated_panel_pdf(VALID, unfolded, output)

    reader = PdfReader(str(output))
    blob_parts: list[str] = []
    for page in reader.pages:
        contents = page.get_contents()
        if contents is None:
            continue
        data = contents.get_data()
        blob_parts.append(data.decode("latin-1", errors="ignore"))
    blob = "\n".join(blob_parts)
    re_count = sum(1 for op in blob.split() if op == "re")
    assert re_count >= 30, f"Expected ≥30 're' (rect) ops in PDF; got {re_count}"


def test_dxf_byte_determinism(tmp_path: Path) -> None:
    """CLAUDE.md §2.4 інваріант: однаковий вхід → байт-у-байт identical DXF."""
    unfolded = unfold_perforated_panel(VALID)
    out1 = tmp_path / "a.dxf"
    out2 = tmp_path / "b.dxf"
    export_perforated_panel_dxf(unfolded, out1)
    export_perforated_panel_dxf(unfolded, out2)
    assert out1.read_bytes() == out2.read_bytes()


def test_pdf_byte_determinism(tmp_path: Path) -> None:
    """CLAUDE.md §2.4 інваріант: PDF теж байт-determinist."""
    unfolded = unfold_perforated_panel(VALID)
    out1 = tmp_path / "a.pdf"
    out2 = tmp_path / "b.pdf"
    export_perforated_panel_pdf(VALID, unfolded, out1)
    export_perforated_panel_pdf(VALID, unfolded, out2)
    assert out1.read_bytes() == out2.read_bytes()


# ── ADR-030/031: ребра, кутові отвори, R5, валідація гибу ─────────────────────


def test_unfold_has_4_corner_holes_and_4_bend_lines() -> None:
    """Cross-розгортка: 4 установочні Ø5.5 + 4 лінії гибу (по краях площини)."""
    u = unfold_perforated_panel(VALID)
    assert len(u.corner_holes) == 4
    assert all(h.shape == "circle" and h.diameter_mm == 5.5 for h in u.corner_holes)
    assert len(u.bend_lines) == 4
    assert u.bend_allowance_mm > 0
    assert u.flat_flange_mm > 0
    assert u.bbox_max_x_mm - u.bbox_min_x_mm > VALID.length_mm
    assert u.bbox_max_y_mm - u.bbox_min_y_mm > VALID.width_mm


def test_dxf_outline_has_8_fillet_arcs(tmp_path: Path) -> None:
    """R5 на 8 вільних кутах ребер → 8 ненульових bulge у outline LWPOLYLINE."""
    unfolded = unfold_perforated_panel(VALID)
    output = tmp_path / "out.dxf"
    export_perforated_panel_dxf(unfolded, output)
    doc = readfile(str(output))
    msp = doc.modelspace()
    polylines = [cast(LWPolyline, e) for e in msp if e.dxftype() == "LWPOLYLINE"]
    outline = max(polylines, key=len)
    bulges = [v[4] for v in outline.get_points()]
    assert sum(1 for b in bulges if abs(b) > 1e-6) == 8


def test_rib_height_too_short_rejected() -> None:
    """rib_height ≤ thickness + bend_radius → flat-фланець ≤ 0 → ValidationError."""
    with pytest.raises(ValidationError):
        PerforatedPanelBuildParameters(
            length_mm=200,
            width_mm=150,
            thickness_mm=10.0,
            hole_size_mm=8,
            pitch_x_mm=30,
            pitch_y_mm=30,
            margin_mm=15,
            rib_height_mm=15,
            bend_radius_mm=5.0,
        )


def test_bend_radius_must_be_in_allowed_set() -> None:
    """bend_radius_mm поза {1.0, 2.5, 4.0, 5.0} → ValidationError (паритет spec)."""
    with pytest.raises(ValidationError):
        PerforatedPanelBuildParameters(
            length_mm=200,
            width_mm=150,
            thickness_mm=2.0,
            hole_size_mm=8,
            pitch_x_mm=30,
            pitch_y_mm=30,
            margin_mm=15,
            rib_height_mm=30,
            bend_radius_mm=1.7,
        )


def test_profile_validation_flags_short_rib() -> None:
    """Server-gate (ADR-019): validate_profile ловить замале ребро."""
    from flatcraft_cad.validate.profile import validate_profile

    errors = validate_profile(
        "perforated_panel",
        {"rib_height_mm": 4.0, "bend_radius_mm": 2.5},
        thickness_mm=2.0,
    )
    assert any(e.code == "FLANGE_TOO_SHORT" and e.field == "rib_height" for e in errors)


def test_bend_validation_applies_to_perforated_panel() -> None:
    """ADR-030/031: перфо-монтажна панель має гиби → bend-валідація активна."""
    from flatcraft_cad.validate.bend import validate_export

    errors = validate_export(
        "perforated_panel",
        {"bend_radius_mm": 99.0, "bend_angle_deg": 90},
        thickness_mm=2.0,
    )
    assert any(e["code"] == "RADIUS_NOT_ALLOWED" for e in errors)


def test_slug_matches_seed() -> None:
    assert PerforatedPanelTemplate.name == "perforated_panel"
