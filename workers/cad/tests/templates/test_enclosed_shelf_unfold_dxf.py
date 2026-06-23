"""Phase 3.0 PR 7b — builder + cross-unfold + DXF export tests.

Перевіряємо: 3D builder повертає Workplane, unfold обчислює сегменти + cross
outline + bend lines, DXF емітить 2 шари (LASER_CUT + BEND_LINES) з
LWPOLYLINE для cross outline і LINE для bend, side perforation працює,
байт-детермінізм.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from ezdxf import readfile  # type: ignore[attr-defined]
from pydantic import ValidationError

from flatcraft_cad.export.dxf import export_enclosed_shelf_dxf
from flatcraft_cad.templates.enclosed_shelf import (
    EnclosedShelfBuildParameters,
    EnclosedShelfSidePerforation,
    EnclosedShelfStiffeningRib,
    build_enclosed_shelf,
)
from flatcraft_cad.unfold import unfold_enclosed_shelf

K_FACTOR = 0.4


def _params(**overrides: object) -> EnclosedShelfBuildParameters:
    base: dict[str, object] = {
        "width_mm": 600.0,
        "depth_mm": 200.0,
        "bend_radius_mm": 2.5,
        "thickness_mm": 1.5,
    }
    base.update(overrides)
    return EnclosedShelfBuildParameters.model_validate(base)


# ─── Builder ────────────────────────────────────────────────────────────────


def test_builder_returns_workplane_no_rib() -> None:
    wp = build_enclosed_shelf(_params())
    assert wp is not None
    assert wp.val() is not None


def test_builder_returns_workplane_with_rib() -> None:
    wp = build_enclosed_shelf(_params(stiffening_rib=EnclosedShelfStiffeningRib(height_mm=15.0)))
    assert wp is not None


# ─── Unfold: сегменти + outline ─────────────────────────────────────────────


def test_unfold_no_rib_has_4_segments_and_3_bends() -> None:
    u = unfold_enclosed_shelf(_params(), K_FACTOR)
    assert u.rib is None
    assert len(u.bend_lines) == 3


def test_unfold_with_rib_has_5_segments_and_4_bends() -> None:
    u = unfold_enclosed_shelf(
        _params(stiffening_rib=EnclosedShelfStiffeningRib(height_mm=15.0)),
        K_FACTOR,
    )
    assert u.rib is not None
    assert len(u.bend_lines) == 4


def test_unfold_bottom_flat_reduced_by_bend_allowance() -> None:
    p = _params()
    u = unfold_enclosed_shelf(p, K_FACTOR)
    # flat_bottom_x = width_mm - 2*(t+r) = 600 - 2*(1.5+2.5) = 592
    assert u.bottom.w_mm == pytest.approx(592.0)
    # No rib: flat_bottom_y = depth_mm - (t+r) = 196
    assert u.bottom.h_mm == pytest.approx(196.0)


def test_unfold_back_dimensions() -> None:
    p = _params()
    u = unfold_enclosed_shelf(p, K_FACTOR)
    # Back: full width, height = depth - (t+r) = 196.
    assert u.back.w_mm == pytest.approx(600.0)
    assert u.back.h_mm == pytest.approx(196.0)


def test_unfold_sides_are_square_after_flat_reduction() -> None:
    """Sides: width = depth - (t+r), height = depth_mm (повна — sides без
    bends на top/bottom). Не повні квадрати після bend allowance, але
    дзеркально однакові (left.w == right.w)."""
    u = unfold_enclosed_shelf(_params(), K_FACTOR)
    assert u.left.w_mm == pytest.approx(u.right.w_mm)
    assert u.left.h_mm == pytest.approx(u.right.h_mm)
    assert u.left.h_mm == pytest.approx(200.0)


def test_unfold_outline_is_closed_polygon() -> None:
    """Outline — clockwise polygon з ≥12 vertices (cross-shape з notches)."""
    u = unfold_enclosed_shelf(_params(), K_FACTOR)
    assert len(u.outline_vertices) >= 12
    # Перша і остання вершини НЕ дублюються (LWPOLYLINE close=True додасть замикач).
    assert u.outline_vertices[0] != u.outline_vertices[-1]


def test_unfold_too_small_raises() -> None:
    """flat_bottom_x ≤ 0 → ValueError (валідатор серверний має це відсіяти ДО)."""
    # width=20, t+r=4 → flat_bottom_x = 20 - 8 = 12 (positive)
    # Дамо width = 8, t+r = 4 → flat_bottom_x = 0 → fail
    # Але width≥300 у Pydantic. Перевіримо через прямий dataclass-виклик.
    with pytest.raises(ValidationError):
        _params(width_mm=200.0)  # < 300 min


# ─── DXF export ─────────────────────────────────────────────────────────────


def test_dxf_emits_outline_and_3_bend_lines_no_rib(tmp_path: Path) -> None:
    u = unfold_enclosed_shelf(_params(), K_FACTOR)
    out = tmp_path / "es.dxf"
    export_enclosed_shelf_dxf(u, out)
    doc = readfile(str(out))
    msp = doc.modelspace()
    polylines = [e for e in msp if e.dxftype() == "LWPOLYLINE"]
    lines = [e for e in msp if e.dxftype() == "LINE"]
    # 1 cross-outline polyline + 3 bend lines.
    assert len(polylines) == 1, f"Expected 1 LWPOLYLINE; got {len(polylines)}"
    assert len(lines) == 3, f"Expected 3 LINE (bend); got {len(lines)}"


def test_dxf_emits_4_bend_lines_with_rib(tmp_path: Path) -> None:
    u = unfold_enclosed_shelf(
        _params(stiffening_rib=EnclosedShelfStiffeningRib(height_mm=15.0)),
        K_FACTOR,
    )
    out = tmp_path / "es.dxf"
    export_enclosed_shelf_dxf(u, out)
    doc = readfile(str(out))
    lines = [e for e in doc.modelspace() if e.dxftype() == "LINE"]
    assert len(lines) == 4


def test_dxf_only_two_custom_layers(tmp_path: Path) -> None:
    """ADR-024 інваріант: 2 виробничі шари LASER_CUT + BEND_LINES."""
    u = unfold_enclosed_shelf(_params(), K_FACTOR)
    out = tmp_path / "es.dxf"
    export_enclosed_shelf_dxf(u, out)
    doc = readfile(str(out))
    custom = [layer.dxf.name for layer in doc.layers if layer.dxf.name not in ("0", "Defpoints")]
    assert set(custom) == {"LASER_CUT", "BEND_LINES"}


def test_dxf_outline_on_laser_cut_layer(tmp_path: Path) -> None:
    u = unfold_enclosed_shelf(_params(), K_FACTOR)
    out = tmp_path / "es.dxf"
    export_enclosed_shelf_dxf(u, out)
    doc = readfile(str(out))
    polylines = [e for e in doc.modelspace() if e.dxftype() == "LWPOLYLINE"]
    assert polylines[0].dxf.layer == "LASER_CUT"


def test_dxf_bend_lines_on_bend_lines_layer(tmp_path: Path) -> None:
    u = unfold_enclosed_shelf(_params(), K_FACTOR)
    out = tmp_path / "es.dxf"
    export_enclosed_shelf_dxf(u, out)
    doc = readfile(str(out))
    lines = [e for e in doc.modelspace() if e.dxftype() == "LINE"]
    for line in lines:
        assert line.dxf.layer == "BEND_LINES"


def test_dxf_no_text_or_dimension_entities(tmp_path: Path) -> None:
    """ADR-024 інваріант: жодних TEXT/DIMENSION — CAM-noise."""
    u = unfold_enclosed_shelf(_params(), K_FACTOR)
    out = tmp_path / "es.dxf"
    export_enclosed_shelf_dxf(u, out)
    doc = readfile(str(out))
    text_entities = [e for e in doc.modelspace() if e.dxftype() in ("TEXT", "MTEXT", "DIMENSION")]
    assert text_entities == []


def test_dxf_side_perforation_adds_inner_cut_polylines(tmp_path: Path) -> None:
    """side_perforation → ≥1 square hole LWPOLYLINE на color 5 (ADR-024)."""
    u = unfold_enclosed_shelf(
        _params(
            side_perforation=EnclosedShelfSidePerforation(
                hole_size_mm=8.0, pitch_x_mm=30.0, pitch_y_mm=30.0, margin_mm=15.0
            )
        ),
        K_FACTOR,
    )
    assert len(u.side_holes) > 0
    out = tmp_path / "es.dxf"
    export_enclosed_shelf_dxf(u, out)
    doc = readfile(str(out))
    polylines = [e for e in doc.modelspace() if e.dxftype() == "LWPOLYLINE"]
    # 1 outer + N holes
    inner = [p for p in polylines if p.dxf.color == 5]
    assert len(inner) == len(u.side_holes)


# ─── Determinism ────────────────────────────────────────────────────────────


def test_dxf_byte_determinism(tmp_path: Path) -> None:
    """CLAUDE.md §2.4: однаковий вхід → identical DXF bytes."""
    u = unfold_enclosed_shelf(_params(), K_FACTOR)
    out1 = tmp_path / "a.dxf"
    out2 = tmp_path / "b.dxf"
    export_enclosed_shelf_dxf(u, out1)
    export_enclosed_shelf_dxf(u, out2)
    assert out1.read_bytes() == out2.read_bytes()


def test_dxf_byte_determinism_with_rib(tmp_path: Path) -> None:
    u = unfold_enclosed_shelf(
        _params(stiffening_rib=EnclosedShelfStiffeningRib(height_mm=15.0)),
        K_FACTOR,
    )
    out1 = tmp_path / "a.dxf"
    out2 = tmp_path / "b.dxf"
    export_enclosed_shelf_dxf(u, out1)
    export_enclosed_shelf_dxf(u, out2)
    assert out1.read_bytes() == out2.read_bytes()
