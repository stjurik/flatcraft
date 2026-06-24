"""Математика наповненості робочої площини отворами — perforated_panel(_square).

Декоративна перфо-панель: плоский лист, centered grid отворів. Цей модуль
ізолює і перевіряє САМЕ математику layout'у (а не DXF/PDF rendering, який
вкритий у test_perforated_panel_square.py):

- скільки отворів влізе: ``n = floor((dim - 2*margin) / pitch) + 1``;
- grid симетрично центрований відносно листа;
- effective margin ніколи не менший за заявлений (інваріант наповненості);
- усі отвори лежать у межах листа й не перетинаються (при pitch > hole_size);
- кругла і квадратна панелі рахують layout ідентично (спільний алгоритм).

Еталонний кейс — декоративна панель з каталогу/seed (perforated_panel_square,
300×100, pitch 27/10, margin 15, □20) → grid 11×8 = 88 отворів.
"""

from __future__ import annotations

import pytest

from flatcraft_cad.templates.perforated_panel import PerforatedPanelBuildParameters
from flatcraft_cad.templates.perforated_panel_square import (
    PerforatedPanelSquareBuildParameters,
)
from flatcraft_cad.unfold import (
    unfold_perforated_panel,
    unfold_perforated_panel_square,
)


def _square(
    *,
    length: float,
    width: float,
    hole: float = 8,
    pitch_x: float = 30,
    pitch_y: float = 30,
    margin: float = 15,
) -> PerforatedPanelSquareBuildParameters:
    return PerforatedPanelSquareBuildParameters(
        length_mm=length,
        width_mm=width,
        thickness_mm=1.5,
        hole_size_mm=hole,
        pitch_x_mm=pitch_x,
        pitch_y_mm=pitch_y,
        margin_mm=margin,
    )


# Еталонна декоративна панель з каталогу (див. PDF skriншот / seed).
CATALOG = _square(length=300, width=100, hole=20, pitch_x=27, pitch_y=10, margin=15)


def test_reproduces_catalog_decorative_panel() -> None:
    """Декоративна панель з каталогу: 300×100, pitch 27/10, margin 15 → 11×8=88.

    Це точний regression еталонного виробу, показаного користувачу у PDF.
    """
    u = unfold_perforated_panel_square(CATALOG)
    assert u.grid_cols == 11
    assert u.grid_rows == 8
    assert len(u.holes) == 88
    # Точна посадка (avail = ціле число кроків) → eff margin == заявлений margin.
    xs = sorted({h.x_mm for h in u.holes})
    ys = sorted({h.y_mm for h in u.holes})
    assert xs[0] == pytest.approx(15.0)
    assert xs[-1] == pytest.approx(300 - 15.0)
    assert ys[0] == pytest.approx(15.0)
    assert ys[-1] == pytest.approx(100 - 15.0)


# (length, width, margin, pitch_x, pitch_y) → (expected_cols, expected_rows).
_COUNT_CASES = [
    pytest.param(300, 100, 15, 27, 10, 11, 8, id="catalog-300x100"),
    pytest.param(200, 150, 15, 30, 30, 6, 5, id="valid-200x150"),
    pytest.param(100, 100, 20, 50, 50, 2, 2, id="small-2x2"),
    pytest.param(1000, 500, 10, 50, 25, 20, 20, id="large-20x20"),
    pytest.param(120, 120, 50, 100, 100, 1, 1, id="single-hole"),
]


@pytest.mark.parametrize(("length", "width", "margin", "px", "py", "cols", "rows"), _COUNT_CASES)
def test_hole_count_math(
    length: float, width: float, margin: float, px: float, py: float, cols: int, rows: int
) -> None:
    """Кількість отворів = floor((dim - 2*margin) / pitch) + 1, по кожній осі."""
    u = unfold_perforated_panel_square(
        _square(length=length, width=width, pitch_x=px, pitch_y=py, margin=margin)
    )
    assert u.grid_cols == cols
    assert u.grid_rows == rows
    # len(holes) завжди == cols * rows (повний прямокутний grid, без дірок).
    assert len(u.holes) == cols * rows


@pytest.mark.parametrize(("length", "width", "margin", "px", "py", "cols", "rows"), _COUNT_CASES)
def test_grid_is_centered_and_symmetric(
    length: float, width: float, margin: float, px: float, py: float, cols: int, rows: int
) -> None:
    """Grid симетрично центрований: відступ зліва == відступ справа.

    Перевіряємо через bounding-box отворів — його центр має збігатись із
    центром листа, а перший/останній отвір — бути дзеркальними.
    """
    u = unfold_perforated_panel_square(
        _square(length=length, width=width, pitch_x=px, pitch_y=py, margin=margin)
    )
    xs = sorted({h.x_mm for h in u.holes})
    ys = sorted({h.y_mm for h in u.holes})
    # Дзеркальність: left_margin == right_margin (з точністю до float).
    assert xs[0] == pytest.approx(length - xs[-1])
    assert ys[0] == pytest.approx(width - ys[-1])
    # Центр bbox отворів == центр листа.
    assert (xs[0] + xs[-1]) / 2 == pytest.approx(length / 2)
    assert (ys[0] + ys[-1]) / 2 == pytest.approx(width / 2)


@pytest.mark.parametrize(("length", "width", "margin", "px", "py", "cols", "rows"), _COUNT_CASES)
def test_effective_margin_never_below_requested(
    length: float, width: float, margin: float, px: float, py: float, cols: int, rows: int
) -> None:
    """Інваріант наповненості: фактичний відступ ≥ заявленого margin_mm.

    Через floor у підрахунку колонок grid ніколи не «вилазить» за робочу
    зону — eff_margin = (dim - (n-1)*pitch)/2 ≥ margin завжди.
    """
    u = unfold_perforated_panel_square(
        _square(length=length, width=width, pitch_x=px, pitch_y=py, margin=margin)
    )
    xs = sorted({h.x_mm for h in u.holes})
    ys = sorted({h.y_mm for h in u.holes})
    assert xs[0] >= margin - 1e-9
    assert ys[0] >= margin - 1e-9
    assert length - xs[-1] >= margin - 1e-9
    assert width - ys[-1] >= margin - 1e-9


def test_holes_stay_within_sheet_bounds() -> None:
    """Жоден отвір (з урахуванням сторони квадрата) не виходить за лист.

    Центр відступає на margin, тож край отвору = center ± hole/2 має лишатись
    усередині 0..dim. Беремо «щільний» кейс (margin 15, □20 → край за 5мм).
    """
    u = unfold_perforated_panel_square(CATALOG)
    half = CATALOG.hole_size_mm / 2
    for h in u.holes:
        assert h.x_mm - half >= 0
        assert h.x_mm + half <= CATALOG.length_mm
        assert h.y_mm - half >= 0
        assert h.y_mm + half <= CATALOG.width_mm


def test_adjacent_hole_spacing_equals_pitch() -> None:
    """Відстань між сусідніми центрами по кожній осі точно == pitch."""
    u = unfold_perforated_panel_square(CATALOG)
    xs = sorted({h.x_mm for h in u.holes})
    ys = sorted({h.y_mm for h in u.holes})
    for a, b in zip(xs, xs[1:], strict=False):
        assert b - a == pytest.approx(CATALOG.pitch_x_mm)
    for a, b in zip(ys, ys[1:], strict=False):
        assert b - a == pytest.approx(CATALOG.pitch_y_mm)


def test_no_overlap_with_clean_grid() -> None:
    """Коли pitch > hole_size по обох осях — отвори не перетинаються.

    Перевіряємо, що проміжок між краями сусідніх отворів додатний:
    gap = pitch - hole_size > 0.
    """
    p = _square(length=200, width=150, hole=8, pitch_x=30, pitch_y=30, margin=15)
    u = unfold_perforated_panel_square(p)
    xs = sorted({h.x_mm for h in u.holes})
    ys = sorted({h.y_mm for h in u.holes})
    for a, b in zip(xs, xs[1:], strict=False):
        assert (b - a) - p.hole_size_mm > 0
    for a, b in zip(ys, ys[1:], strict=False):
        assert (b - a) - p.hole_size_mm > 0


# (pitch, hole_size) → чи перетинаються сусідні отвори (gap = pitch - hole < 0).
_OVERLAP_CASES = [
    pytest.param(30, 8, False, id="pitch>hole-clean"),
    pytest.param(20, 20, True, id="pitch==hole-touching"),
    pytest.param(10, 20, True, id="catalog-y-axis-overlap"),
    pytest.param(27, 20, False, id="catalog-x-axis-clean"),
]


@pytest.mark.parametrize(("pitch", "hole", "overlaps"), _OVERLAP_CASES)
def test_overlap_math_detects_merged_holes(pitch: float, hole: float, overlaps: bool) -> None:
    """Математика наповненості: отвори зливаються, коли pitch ≤ hole_size.

    Це фіксує діагностичну формулу. NB: еталонна панель з каталогу має
    pitch_y=10 < □20 → отвори по Y зливаються у вертикальні прорізи (gap<0),
    хоча BOM рахує їх як 88 окремих отворів. Серверної валідації цього кейсу
    наразі немає — див. розмову з користувачем.
    """
    gap = pitch - hole
    assert (gap < 0 or gap == 0) == overlaps


def test_all_hole_positions_unique() -> None:
    """Grid не дублює позицій — set координат == кількості отворів."""
    u = unfold_perforated_panel_square(CATALOG)
    positions = {(h.x_mm, h.y_mm) for h in u.holes}
    assert len(positions) == len(u.holes) == 88


def test_single_hole_when_pitch_exceeds_available() -> None:
    """Коли крок більший за робочу зону — рівно 1 отвір по центру листа."""
    p = _square(length=120, width=120, pitch_x=100, pitch_y=100, margin=50)
    u = unfold_perforated_panel_square(p)
    assert u.grid_cols == 1
    assert u.grid_rows == 1
    assert len(u.holes) == 1
    assert u.holes[0].x_mm == pytest.approx(60.0)
    assert u.holes[0].y_mm == pytest.approx(60.0)


def test_round_and_square_share_identical_layout_math() -> None:
    """Кругла і квадратна панелі рахують grid однаково (спільний алгоритм).

    При однакових length/width/pitch/margin позиції центрів і кількість
    отворів мусять збігатись — різниця лише у `shape`.
    """
    square = unfold_perforated_panel_square(
        _square(length=300, width=100, hole=20, pitch_x=27, pitch_y=10, margin=15)
    )
    circle = unfold_perforated_panel(
        PerforatedPanelBuildParameters(
            length_mm=300,
            width_mm=100,
            thickness_mm=1.5,
            hole_diameter_mm=20,
            pitch_x_mm=27,
            pitch_y_mm=10,
            margin_mm=15,
        )
    )
    assert (square.grid_cols, square.grid_rows) == (circle.grid_cols, circle.grid_rows)
    sq_pos = sorted((h.x_mm, h.y_mm) for h in square.holes)
    ci_pos = sorted((h.x_mm, h.y_mm) for h in circle.holes)
    assert sq_pos == ci_pos
    assert all(h.shape == "square" for h in square.holes)
    assert all(h.shape == "circle" for h in circle.holes)
