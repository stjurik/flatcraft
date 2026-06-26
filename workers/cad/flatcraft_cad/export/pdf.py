"""PDF-експорт листозгинальної заготовки.

Структура одної сторінки A4-landscape:

    ┌─────────────────────────────────────────────────────────────────┐
    │ HEADER: назва шаблону · slug · дата · артикул (hash params)     │
    ├──────────────────────────────────┬──────────────────────────────┤
    │ РОЗГОРТКА (top-down)             │ ТАБЛИЦЯ ГИБІВ                │
    │ • прямокутник length × width     │ ┌────────────────────────┐   │
    │ • bend line штрихована           │ │ # | Кут | R | Довжина  │   │
    │ • розміри: довжина + ширина      │ │ 1 | 90° | 2.5 | 100 мм │   │
    │                                  │ └────────────────────────┘   │
    │                                  │ BOM                          │
    │                                  │ • Матеріал, товщина          │
    │                                  │ • Площа, об'єм, маса         │
    ├──────────────────────────────────┴──────────────────────────────┤
    │ FOOTER: QR-код permalink · виробник підказки                    │
    └─────────────────────────────────────────────────────────────────┘

Ізометрія (Phase 2.9.e, ADR-025): довідковий векторний каркас згорнутого виробу
у правій колонці під таблицею гибів. Будуємо через OCC hidden-line-removal
(`export/isometric.py`) із 3D-solid, який worker уже рахує (`build_*`); отвори
згортаємо назад на грані (`export/isometry_solid.py`). Видимі ребра — суцільні,
приховані — пунктирні. Залишається байт-у-байт детермінованим (pure vector).

Детермінізм (CLAUDE.md §2.4): однакові params → байт-у-байт ідентичний PDF.
ReportLab вставляє timestamp у metadata; постобробку timestamp/ID робимо
у `_normalize_pdf_bytes` як для DXF (Phase 1.8).
"""

from __future__ import annotations

import hashlib
import io
import json
import math
import re
from datetime import UTC, datetime
from pathlib import Path
from typing import Final

import cadquery as cq
import qrcode
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas as pdfcanvas

from flatcraft_cad.export.dimensions import (
    FinishedDimsParams,
    compute_finished_dimensions,
    format_dimensions,
)
from flatcraft_cad.export.fonts import register_fonts
from flatcraft_cad.export.isometric import IsoPolyline, fit_to_box, project_isometric
from flatcraft_cad.export.isometry_solid import with_isometry_holes
from flatcraft_cad.export.layout.bend_badges import (
    BADGE_DIAMETER_MM,
    BendBadge,
    BendLine2D,
    place_bend_badges,
)
from flatcraft_cad.export.layout.corner_picker import (
    BBox2D,
    Corner,
    Size2D,
    pick_annotation_corner,
)
from flatcraft_cad.export.layout.hole_dims import should_dim_individual_holes
from flatcraft_cad.materials.industry_names import format_material_label
from flatcraft_cad.templates.corner_angle import CornerAngleBuildParameters
from flatcraft_cad.templates.enclosed_shelf import EnclosedShelfBuildParameters
from flatcraft_cad.templates.l_bracket import LBracketBuildParameters
from flatcraft_cad.templates.perforated_panel import PerforatedPanelBuildParameters
from flatcraft_cad.templates.perforated_panel_square import (
    CORNER_HOLE_DIAMETER_MM,
    PerforatedPanelSquareBuildParameters,
)
from flatcraft_cad.templates.wall_shelf import WallShelfBuildParameters
from flatcraft_cad.templates.z_bracket import ZBracketBuildParameters
from flatcraft_cad.unfold import (
    Hole2D,
    UnfoldedCornerAngle,
    UnfoldedEnclosedShelf,
    UnfoldedLBracket,
    UnfoldedPerforatedPanel,
    UnfoldedPerforatedPanelSquare,
    UnfoldedWallShelf,
    UnfoldedZBracket,
)

register_fonts()

PAGE_WIDTH, PAGE_HEIGHT = landscape(A4)

# Phase X.1 B (ADR-020): soft-launch watermark «BETA» у footer кожної сторінки.
# Прапор модуль-level — щоб вимкнути одним рядком при v1.0-релізі.
BETA_WATERMARK = True
FEEDBACK_EMAIL = "feedback@hart.crimea.ua"
# Текст водяного знака: курсивний subtle-рядок над нижнім краєм. Реальний
# email + публічний GitHub (без dead-link на Discord, якого ще нема).
_BETA_WATERMARK_TEXT: Final[str] = (
    f"BETA · Знайшли помилку? {FEEDBACK_EMAIL} · спільнота: github.com/stjurik/flatcraft"
)

# Спільний layout bend-table (7 колонок з «Напрям»). Сума = 113 мм, при
# origin x=175 → 288 < 297 (landscape A4), вміщається без overflow.
_BEND_TABLE_HEADER: Final[tuple[str, ...]] = (
    "#",
    "Кут,°",
    "R,мм",
    "Довж,мм",
    "K",
    "BA,мм",
    "Напрям",
)
_BEND_TABLE_COL_WIDTHS_MM: Final[tuple[float, ...]] = (8, 16, 18, 22, 13, 18, 18)


def _direction_label(direction: str) -> str:
    """Текстова позначка напряму згину для PDF: UP / DOWN (без стрілок ↓/↑)."""
    return "UP" if direction == "up" else "DOWN"


def _draw_beta_watermark(
    c: pdfcanvas.Canvas,
    page_width: float,
    page_height: float,
) -> None:
    """Центрований subtle-watermark «BETA · feedback» унизу сторінки.

    Pure-рендер: 7pt курсив, сірий #707070, 18pt від нижнього краю — нижче
    реального контенту (footer-hint на 15мм, QR на 12мм), тож не перекриває.
    `page_height` приймається для повноти сигнатури (footer-anchor — від низу).
    Керується прапором BETA_WATERMARK (вимкнення при v1.0).
    """
    if not BETA_WATERMARK:
        return
    _ = page_height
    c.saveState()
    c.setFont("DejaVuSans-Oblique", 7)
    c.setFillColorRGB(0x70 / 255, 0x70 / 255, 0x70 / 255)
    c.drawCentredString(page_width / 2, 18, _BETA_WATERMARK_TEXT)
    c.restoreState()


def _draw_finished_dims_line(
    c: pdfcanvas.Canvas,
    template_slug: str,
    params: FinishedDimsParams,
    *,
    y_mm: float = 210 - 28,
) -> None:
    """Рядок header'а «Габарити готового виробу: X × Y × Z мм» (Phase 2.9.b Block C).

    Нижче рядка з розмірами розгортки/матеріалом. Той самий шрифт header'а
    (DejaVuSans 10pt). Габарит — bbox зігнутої деталі (dimensions.py)."""
    dims = compute_finished_dimensions(template_slug, params)
    c.setFont("DejaVuSans", 10)
    c.drawString(15 * mm, y_mm * mm, f"Габарити готового виробу: {format_dimensions(dims)}")


def _draw_bend_badges(
    c: pdfcanvas.Canvas,
    badges: tuple[BendBadge, ...],
    *,
    x0_pt: float,
    y0_pt: float,
    scale: float,
) -> None:
    """Малює badge-кола з номерами гибів на розгортці (Phase 2.9.b Block B).

    Позиції badge'ів приходять у model-space мм; (x0_pt, y0_pt, scale)
    переводять їх у точки канви. Коло — ФІКСОВАНОГО розміру на папері
    (Ø5мм), щоб лишалось читабельним незалежно від масштабу розгортки;
    лише його центр масштабується разом з геометрією.
    """
    badge_r_pt = (BADGE_DIAMETER_MM / 2.0) * mm
    for badge in badges:
        cx = x0_pt + badge.x_mm * scale * mm
        cy = y0_pt + badge.y_mm * scale * mm
        if badge.has_leader:
            lx = x0_pt + badge.leader_to_x_mm * scale * mm
            ly = y0_pt + badge.leader_to_y_mm * scale * mm
            c.saveState()
            c.setLineWidth(0.3)
            c.setStrokeColorRGB(0, 0, 0)
            c.line(cx, cy, lx, ly)
            c.restoreState()
        c.saveState()
        c.setFillColorRGB(0xFA / 255, 0xFA / 255, 0xFA / 255)
        c.setStrokeColorRGB(0, 0, 0)
        c.setLineWidth(0.5)
        c.circle(cx, cy, badge_r_pt, stroke=1, fill=1)
        c.setFillColorRGB(0, 0, 0)
        c.setFont("DejaVuSans-Bold", 8)
        # drawCentredString центрує по X; -2.8pt опускає baseline до візуального центру 8pt.
        c.drawCentredString(cx, cy - 2.8, str(badge.number))
        c.restoreState()


def _draw_hole_dims(
    c: pdfcanvas.Canvas,
    holes: tuple[Hole2D, ...],
    *,
    x0_pt: float,
    y0_pt: float,
    scale: float,
    part_top_pt: float,
) -> None:
    """Ø-виноски отворів на розгортці (Phase 2.9.b Block F).

    ≤ cap отворів → коротка виноска-риска + текст «Ø8» біля кожного. Інакше
    (перфо-панель) → одна виноска на першому + анотація «×N отворів Ø8» над
    деталлю, щоб не захаращувати креслення сотнями підписів."""
    individual = should_dim_individual_holes(len(holes))
    targets = holes if individual else holes[:1]
    c.saveState()
    c.setStrokeColorRGB(0.8, 0.2, 0.2)
    c.setFillColorRGB(0.8, 0.2, 0.2)
    c.setLineWidth(0.3)
    c.setFont("DejaVuSans", 7)
    # Phase 3.0 PR 5 (ADR-027 Рішення 6): square holes → '□' замість 'Ø'.
    # `diameter_mm` для square означає side length.
    prefix = "□" if (holes and holes[0].shape == "square") else "Ø"
    for hole in targets:
        cx = x0_pt + hole.x_mm * scale * mm
        cy = y0_pt + hole.y_mm * scale * mm
        r = (hole.diameter_mm / 2.0) * scale * mm
        # Виноска з верхньо-правого краю кола назовні під 45°.
        lx, ly = cx + r * 0.707, cy + r * 0.707
        tx, ty = lx + 3 * mm, ly + 3 * mm
        c.line(lx, ly, tx, ty)
        c.drawString(tx + 0.5 * mm, ty - 1 * mm, f"{prefix}{hole.diameter_mm:g}")
    if not individual:
        c.setFont("DejaVuSans", 8)
        c.drawString(
            x0_pt,
            part_top_pt + 4 * mm,
            f"×{len(holes)} отворів {prefix}{holes[0].diameter_mm:g}",
        )
    c.setFillColorRGB(0, 0, 0)
    c.restoreState()


def _bend_badges_for(
    bend_positions_mm: tuple[float, ...], width_mm: float
) -> tuple[BendBadge, ...]:
    """Будує BendLine2D для кожної вертикальної лінії гибу і розкладає badge'і."""
    lines = tuple(
        BendLine2D(number=n + 1, x_mm=bend_mm, y_start_mm=0.0, y_end_mm=width_mm)
        for n, bend_mm in enumerate(bend_positions_mm)
    )
    return place_bend_badges(lines)


def _draw_bend_table_rows(
    c: pdfcanvas.Canvas,
    body_rows: list[tuple[str, ...]],
    *,
    origin_mm: tuple[float, float],
) -> None:
    """Малює таблицю гибів (header + рядки) зі спільним layout'ом."""
    ox, oy = origin_mm
    c.setFont("DejaVuSans-Bold", 10)
    c.drawString(ox * mm, oy * mm, "Гиби")
    rows: list[tuple[str, ...]] = [_BEND_TABLE_HEADER, *body_rows]
    row_h_mm = 6
    cur_y_mm = oy - 7
    c.setLineWidth(0.4)
    for r_idx, row in enumerate(rows):
        cur_x_mm = ox
        if r_idx == 0:
            c.setFont("DejaVuSans-Bold", 8)
        else:
            c.setFont("DejaVuSans", 9)
        for cell, w_mm in zip(row, _BEND_TABLE_COL_WIDTHS_MM, strict=True):
            c.rect(cur_x_mm * mm, cur_y_mm * mm, w_mm * mm, row_h_mm * mm, stroke=1, fill=0)
            c.drawString((cur_x_mm + 1) * mm, (cur_y_mm + 1.5) * mm, cell)
            cur_x_mm += w_mm
        cur_y_mm -= row_h_mm


# Уніфікована таблиця розмірів (PR 8c, issue #5): 2 колонки «Параметр | Значення»,
# той самий visual style, що `_draw_bend_table_rows`. Замінює неструктуровані
# текстові блоки на перфо-панелях/закритій полиці.
_DIMS_TABLE_HEADER: Final[tuple[str, str]] = ("Параметр", "Значення")
_DIMS_TABLE_COL_WIDTHS_MM: Final[tuple[float, float]] = (60.0, 50.0)


def _draw_dimensions_table(
    c: pdfcanvas.Canvas,
    title: str,
    body_rows: list[tuple[str, str]],
    *,
    origin_mm: tuple[float, float],
) -> float:
    """Малює `[title]` + 2-колонкову таблицю «Параметр | Значення».

    Повертає Y-координату (у мм) НИЖНЬОГО краю таблиці — для наступних
    блоків, що мають слідувати за нею (BOM/grid summary).
    """
    ox, oy = origin_mm
    c.setFont("DejaVuSans-Bold", 10)
    c.drawString(ox * mm, oy * mm, title)
    rows: list[tuple[str, str]] = [_DIMS_TABLE_HEADER, *body_rows]
    row_h_mm = 6
    cur_y_mm = oy - 7
    c.setLineWidth(0.4)
    for r_idx, row in enumerate(rows):
        cur_x_mm = ox
        if r_idx == 0:
            c.setFont("DejaVuSans-Bold", 8)
        else:
            c.setFont("DejaVuSans", 9)
        for cell, w_mm in zip(row, _DIMS_TABLE_COL_WIDTHS_MM, strict=True):
            c.rect(cur_x_mm * mm, cur_y_mm * mm, w_mm * mm, row_h_mm * mm, stroke=1, fill=0)
            c.drawString((cur_x_mm + 1) * mm, (cur_y_mm + 1.5) * mm, cell)
            cur_x_mm += w_mm
        cur_y_mm -= row_h_mm
    return cur_y_mm


def compute_bom(
    unfolded: (
        UnfoldedLBracket
        | UnfoldedZBracket
        | UnfoldedCornerAngle
        | UnfoldedWallShelf
        | UnfoldedPerforatedPanel
        | UnfoldedPerforatedPanelSquare
    ),
    *,
    density_kg_m3: float = 7850.0,
) -> dict[str, float]:
    """Bill of materials для розгорнутого аркуша.

    Pure-функція, відокремлена від PDF-рендерингу — щоб числа можна
    було перевіряти юніт-тестами без парсингу PDF (Cyrillic у DejaVuSans
    PDF не екстрактується pypdf). Працює з будь-яким Unfolded* dataclass,
    що має length_mm/width_mm/thickness_mm fields (L, Z, U/wall_shelf).
    """
    area_mm2 = unfolded.length_mm * unfolded.width_mm
    volume_mm3 = area_mm2 * unfolded.thickness_mm
    mass_kg = (volume_mm3 / 1e9) * density_kg_m3
    return {
        "area_mm2": area_mm2,
        "area_m2": area_mm2 / 1e6,
        # Площа фарбування — обидва боки листа (Phase 2.9.b Block D).
        "area_paint_m2": (area_mm2 / 1e6) * 2.0,
        "volume_m3": volume_mm3 / 1e9,
        "mass_g": mass_kg * 1000.0,  # збережено для зворотної сумісності
        "mass_kg": mass_kg,
    }


def bom_text_lines(
    *,
    material_label: str,
    thickness_mm: float,
    bom: dict[str, float],
    include_volume: bool = True,
) -> list[str]:
    """Рядки BOM-секції українською (Phase 2.9.b Block D).

    Pure-функція (без canvas) — щоб юніт-тестувати лейбли/округлення без PDF.
    Округлення: товщина 0.01мм, площа 0.001-0.0001 м², маса 0.01 кг. Лейбли
    суто українські; англійською лишається тільки значення material_label.

    `material_label` — це material_code (slug); Hotfix 2.9.d форматує його у
    industry-назву (`DC01 (ДСТУ EN 10130) — холоднокатана сталь`), щоб виробник
    розумів, що замовляти. Невідомий код → сирий код + WARNING (не падає).
    """
    lines = [
        f"Матеріал: {format_material_label(material_label)}",
        f"Товщина: {thickness_mm:.2f} мм",
        f"Площа заготовки: {bom['area_m2']:.4f} м² ({bom['area_mm2']:.0f} мм²)",
        f"Площа фарбування: {bom['area_paint_m2']:.3f} м²",
    ]
    if include_volume:
        lines.append(f"Об'єм: {bom['volume_m3']:.6f} м³")
    lines.append(f"Маса: {bom['mass_kg']:.2f} кг")
    return lines


# Геометрія правої колонки анотацій (page-mm) для auto-layout (Phase 2.9.b E).
_BEND_TABLE_TOP_MM: Final[float] = 170.0
_BEND_ROW_H_MM: Final[float] = 6.0
_ANNOT_COLUMN: Final[BBox2D] = BBox2D(173.0, 50.0, 290.0, 175.0)
_BOM_SIZE: Final[Size2D] = Size2D(75.0, 28.0)
_BOM_CLASSIC_ORIGIN: Final[tuple[float, float]] = (175.0, 140.0)


def _choose_bom_origin(n_bend_rows: int) -> tuple[float, float]:
    """Вибирає origin BOM-блоку у правій колонці під таблицею гибів (Block E).

    Corner picker перевіряє, чи під таблицею є вільний кут (BL/BR) у колонці
    анотацій. Якщо так — BOM лягає на фіксований відступ під ФАКТИЧНИМ низом
    таблиці (слідує за нею, коли в таблиці більше рядків — Z/wall_shelf).
    Інакше — класичний слот. Тест-orient: pure-функція pick_annotation_corner
    покрита окремо; тут лише маппінг у координати."""
    rows_total = n_bend_rows + 1  # + рядок-заголовок
    table_bottom = _BEND_TABLE_TOP_MM - rows_total * _BEND_ROW_H_MM
    table_bbox = BBox2D(173.0, table_bottom, 290.0, _BEND_TABLE_TOP_MM)
    corner = pick_annotation_corner(table_bbox, _ANNOT_COLUMN, _BOM_SIZE, margin_mm=4.0)
    if corner in (Corner.BL, Corner.BR):
        return (175.0, table_bottom - 6.0)
    return _BOM_CLASSIC_ORIGIN


def _draw_bom_block(
    c: pdfcanvas.Canvas,
    *,
    material_label: str,
    thickness_mm: float,
    bom: dict[str, float],
    origin_mm: tuple[float, float],
    include_volume: bool = True,
) -> None:
    """Малює секцію BOM (заголовок + рядки) зі спільним layout'ом для всіх шаблонів."""
    ox, oy = origin_mm
    c.setFont("DejaVuSans-Bold", 10)
    c.drawString(ox * mm, oy * mm, "Специфікація матеріалів (BOM)")
    c.setFont("DejaVuSans", 9)
    lines = bom_text_lines(
        material_label=material_label,
        thickness_mm=thickness_mm,
        bom=bom,
        include_volume=include_volume,
    )
    for i, line in enumerate(lines):
        c.drawString(ox * mm, (oy - 4 - i * 4) * mm, line)


# Ізометрія — слот у нижній частині правої колонки, над QR (Phase 2.9.e).
_ISO_ORIGIN_MM: Final[tuple[float, float]] = (178.0, 52.0)
_ISO_BOX_MM: Final[tuple[float, float]] = (96.0, 44.0)


def _draw_isometric(
    c: pdfcanvas.Canvas,
    solid: cq.Workplane,
    params: object,
    unfolded: object,
    *,
    origin_mm: tuple[float, float] = _ISO_ORIGIN_MM,
    box_mm: tuple[float, float] = _ISO_BOX_MM,
    title: str = "Ізометрія (довідково)",
) -> None:
    """Малює векторну ізометрію виробу (Phase 2.9.e, ADR-025).

    Згортає отвори на грані → HLR-проєкція → видимі ребра суцільні, приховані
    пунктирні. Полілайни вписуються у бокс зі збереженням пропорцій. Якщо
    проєкція порожня (теоретично) — мовчки пропускаємо, щоб не валити експорт.
    """
    holed = with_isometry_holes(params, unfolded, solid)
    visible, hidden = project_isometric(holed)
    polylines = (*visible, *hidden)
    if not polylines:
        return

    box_w, box_h = box_mm
    scale, tx, ty = fit_to_box(polylines, box_w, box_h)
    ox, oy = origin_mm

    c.setFont("DejaVuSans-Bold", 9)
    c.drawString(ox * mm, (oy + box_h + 2) * mm, title)

    def _stroke(group: tuple[IsoPolyline, ...], *, dashed: bool) -> None:
        c.saveState()
        if dashed:
            c.setDash(2, 2)
            c.setStrokeColorRGB(0.45, 0.45, 0.45)
            c.setLineWidth(0.3)
        else:
            c.setStrokeColorRGB(0, 0, 0)
            c.setLineWidth(0.4)
        for poly in group:
            pts = [((ox + x * scale + tx) * mm, (oy + y * scale + ty) * mm) for x, y in poly]
            c.lines([(*pts[i], *pts[i + 1]) for i in range(len(pts) - 1)])
        c.restoreState()

    # Приховані спершу, видимі поверх.
    _stroke(hidden, dashed=True)
    _stroke(visible, dashed=False)


# Метадані з фіксованою датою/ID для байт-у-байт детермінізму.
_FROZEN_DATE = "D:20260101000000+00'00'"
_FROZEN_ID = "[<00000000000000000000000000000001> <00000000000000000000000000000002>]"

_PDF_INFO_DATE_RE: Final[re.Pattern[bytes]] = re.compile(rb"D:\d{14}[+\-]\d{2}'\d{2}'")
_PDF_ID_RE: Final[re.Pattern[bytes]] = re.compile(rb"\[<[0-9A-Fa-f]+>\s*<[0-9A-Fa-f]+>\]")


def _article_hash(parameters: LBracketBuildParameters) -> str:
    """Стабільний короткий ID партії на основі параметрів. Однакові
    розміри → однаковий артикул → користувач упізнає re-export."""
    serialised = json.dumps(parameters.model_dump(), sort_keys=True)
    return hashlib.sha256(serialised.encode("utf-8")).hexdigest()[:10].upper()


def _make_qr_png(text: str) -> bytes:
    qr = qrcode.QRCode(
        version=2,
        error_correction=qrcode.constants.ERROR_CORRECT_M,
        box_size=4,
        border=2,
    )
    qr.add_data(text)
    qr.make(fit=True)
    img = qr.make_image(fill_color="black", back_color="white")
    buf = io.BytesIO()
    # qrcode stubs типують лише PyPNGImage у return; runtime повертає
    # PIL.Image коли image_factory не задано — `format` приймає.
    img.save(buf, format="PNG")  # type: ignore[call-arg]
    return buf.getvalue()


def _draw_unfold(
    c: pdfcanvas.Canvas,
    unfolded: UnfoldedLBracket,
    *,
    origin_mm: tuple[float, float],
    canvas_size_mm: tuple[float, float],
    bend_radius_mm: float = 0.0,
    bend_direction: str = "down",
) -> None:
    """Малює розгортку у канвасі. Координати у мм від origin (lower-left)."""
    ox_mm, oy_mm = origin_mm
    canvas_w, canvas_h = canvas_size_mm
    scale = min(canvas_w / max(unfolded.length_mm, 1), canvas_h / max(unfolded.width_mm, 1))
    w = unfolded.length_mm * scale
    h = unfolded.width_mm * scale
    bend_x = unfolded.bend_position_mm * scale

    x0 = (ox_mm + (canvas_w - w) / 2) * mm
    y0 = (oy_mm + (canvas_h - h) / 2) * mm

    # Outer rectangle.
    c.setLineWidth(1.0)
    c.rect(x0, y0, w * mm, h * mm, stroke=1, fill=0)

    # Bend line — dashed vertical.
    c.saveState()
    c.setDash(4, 3)
    c.setStrokeColorRGB(0.2, 0.4, 0.8)
    c.line(x0 + bend_x * mm, y0, x0 + bend_x * mm, y0 + h * mm)
    c.restoreState()

    # Bend number badge ПОСЕРЕДИНІ лінії (Phase 2.9.b Block B).
    _draw_bend_badges(
        c,
        _bend_badges_for((unfolded.bend_position_mm,), unfolded.width_mm),
        x0_pt=x0,
        y0_pt=y0,
        scale=scale,
    )

    # Annotations: length / width / bend position.
    c.setFont("DejaVuSans", 8)
    c.drawCentredString(x0 + (w * mm) / 2, y0 - 4 * mm, f"L = {unfolded.length_mm:.2f} мм")
    c.saveState()
    c.translate(x0 - 5 * mm, y0 + (h * mm) / 2)
    c.rotate(90)
    c.drawCentredString(0, 0, f"W = {unfolded.width_mm:.2f} мм")
    c.restoreState()
    c.setFillColorRGB(0.2, 0.4, 0.8)
    label = _direction_label(bend_direction)
    callout = f"BEND #1 {label} R{bend_radius_mm:g} d={unfolded.bend_position_mm:.1f}мм"
    c.drawCentredString(x0 + bend_x * mm, y0 + h * mm + 2 * mm, callout)
    c.setFillColorRGB(0, 0, 0)


def _draw_bend_table(
    c: pdfcanvas.Canvas,
    parameters: LBracketBuildParameters,
    unfolded: UnfoldedLBracket,
    *,
    origin_mm: tuple[float, float],
) -> None:
    body_rows: list[tuple[str, ...]] = [
        (
            "1",
            f"{parameters.bend_angle_deg}",
            f"{parameters.bend_radius_mm}",
            f"{parameters.width_mm:.1f}",
            "0.40",
            f"{unfolded.bend_allowance_mm:.2f}",
            _direction_label(parameters.bend_direction),
        ),
    ]
    _draw_bend_table_rows(c, body_rows, origin_mm=origin_mm)


def _draw_bom(
    c: pdfcanvas.Canvas,
    parameters: LBracketBuildParameters,
    unfolded: UnfoldedLBracket,
    *,
    material_label: str,
    density_kg_m3: float,
    origin_mm: tuple[float, float],
) -> None:
    _draw_bom_block(
        c,
        material_label=material_label,
        thickness_mm=unfolded.thickness_mm,
        bom=compute_bom(unfolded, density_kg_m3=density_kg_m3),
        origin_mm=origin_mm,
    )


def _normalize_pdf_bytes(path: Path) -> None:
    """Перепризначає runtime-залежні поля (timestamp, ID) на frozen,
    щоб однакові params → байт-у-байт ідентичний PDF."""
    data = path.read_bytes()
    data = _PDF_INFO_DATE_RE.sub(_FROZEN_DATE.encode("ascii"), data)
    data = _PDF_ID_RE.sub(_FROZEN_ID.encode("ascii"), data)
    path.write_bytes(data)


def export_l_bracket_pdf(
    parameters: LBracketBuildParameters,
    unfolded: UnfoldedLBracket,
    output_path: Path,
    *,
    solid: cq.Workplane | None = None,
    material_label: str = "cold_rolled_steel",
    density_kg_m3: float = 7850.0,
    permalink_url: str | None = None,
) -> Path:
    """Збирає PDF з розгорткою, таблицею гибів, BOM і QR-кодом."""
    article = _article_hash(parameters)
    qr_payload = permalink_url or f"flatcraft://l_bracket/{article}"

    c = pdfcanvas.Canvas(str(output_path), pagesize=landscape(A4))
    c.setTitle(f"L-bracket {article}")
    c.setAuthor("flatcraft")
    c.setCreator("flatcraft-cad-worker")
    c.setProducer("flatcraft-cad-worker")
    c.setSubject(f"L-bracket {parameters.leg_a_mm}×{parameters.leg_b_mm}×{parameters.width_mm} мм")

    # Header.
    c.setFont("DejaVuSans-Bold", 14)
    c.drawString(15 * mm, (210 - 15) * mm, "L-кронштейн")
    c.setFont("DejaVuSans", 10)
    today = datetime.now(UTC).strftime("%Y-%m-%d")
    c.drawString(
        15 * mm,
        (210 - 20) * mm,
        f"slug: l_bracket · артикул: {article} · дата: {today}",
    )
    c.drawString(
        15 * mm,
        (210 - 24) * mm,
        f"Розміри (зовн.): A={parameters.leg_a_mm} · B={parameters.leg_b_mm} · "
        f"W={parameters.width_mm} мм · R={parameters.bend_radius_mm} мм",
    )
    _draw_finished_dims_line(c, "l_bracket", parameters)

    # Layout.
    # Розгортка ліворуч (~150×110 мм), таблиці/BOM/QR праворуч.
    _draw_unfold(
        c,
        unfolded,
        origin_mm=(15, 70),
        canvas_size_mm=(150, 100),
        bend_radius_mm=parameters.bend_radius_mm,
        bend_direction=parameters.bend_direction,
    )
    _draw_bend_table(c, parameters, unfolded, origin_mm=(175, 170))
    _draw_bom(
        c,
        parameters,
        unfolded,
        material_label=material_label,
        density_kg_m3=density_kg_m3,
        origin_mm=_choose_bom_origin(1),
    )
    if solid is not None:
        _draw_isometric(c, solid, parameters, unfolded)

    # QR-код у footer-area.
    qr_png = _make_qr_png(qr_payload)
    qr_size_mm = 30
    qr_buf = io.BytesIO(qr_png)
    c.drawImage(
        # ReportLab приймає image як filename або ImageReader; через ImageReader.
        _ImageReader(qr_buf),
        (PAGE_WIDTH / mm - qr_size_mm - 15) * mm,
        15 * mm,
        width=qr_size_mm * mm,
        height=qr_size_mm * mm,
    )
    c.setFont("DejaVuSans", 7)
    c.drawString(
        (PAGE_WIDTH / mm - qr_size_mm - 15) * mm,
        12 * mm,
        f"QR: {qr_payload[:48]}",
    )

    # Footer hint.
    c.setFont("DejaVuSans-Oblique", 8)
    c.drawString(
        15 * mm,
        15 * mm,
        "DXF для лазерного різання · BEND-LINES = лінія гиба (не різати)",
    )

    _draw_beta_watermark(c, PAGE_WIDTH, PAGE_HEIGHT)
    c.showPage()
    c.save()

    _normalize_pdf_bytes(output_path)
    return output_path


def export_z_bracket_pdf(
    parameters: ZBracketBuildParameters,
    unfolded: UnfoldedZBracket,
    output_path: Path,
    *,
    solid: cq.Workplane | None = None,
    material_label: str = "cold_rolled_steel",
    density_kg_m3: float = 7850.0,
    permalink_url: str | None = None,
) -> Path:
    """PDF для Z-bracket: 2 паралельні bend lines + 2 рядки у bend table."""
    import hashlib
    import json

    article = (
        hashlib.sha256(json.dumps(parameters.model_dump(), sort_keys=True).encode("utf-8"))
        .hexdigest()[:10]
        .upper()
    )
    qr_payload = permalink_url or f"flatcraft://z_bracket/{article}"

    c = pdfcanvas.Canvas(str(output_path), pagesize=landscape(A4))
    c.setTitle(f"Z-bracket {article}")
    c.setAuthor("flatcraft")
    c.setCreator("flatcraft-cad-worker")
    c.setProducer("flatcraft-cad-worker")
    c.setSubject(
        f"Z-bracket {parameters.top_flange_mm}/{parameters.offset_mm}/"
        f"{parameters.bottom_flange_mm}×{parameters.width_mm} мм",
    )

    c.setFont("DejaVuSans-Bold", 14)
    c.drawString(15 * mm, (210 - 15) * mm, "Z-кронштейн")
    c.setFont("DejaVuSans", 10)
    today = datetime.now(UTC).strftime("%Y-%m-%d")
    c.drawString(
        15 * mm,
        (210 - 20) * mm,
        f"slug: z_bracket · артикул: {article} · дата: {today}",
    )
    c.drawString(
        15 * mm,
        (210 - 24) * mm,
        f"Розміри: top={parameters.top_flange_mm} · offset={parameters.offset_mm} · "
        f"bottom={parameters.bottom_flange_mm} · W={parameters.width_mm} мм · "
        f"R={parameters.bend_radius_mm} мм",
    )
    _draw_finished_dims_line(c, "z_bracket", parameters)

    # Розгортка з двома bend lines.
    _draw_unfold_generic(
        c,
        length_mm=unfolded.length_mm,
        width_mm=unfolded.width_mm,
        bend_positions_mm=unfolded.bend_positions_mm,
        origin_mm=(15, 70),
        canvas_size_mm=(150, 100),
        bend_radius_mm=parameters.bend_radius_mm,
        bend_directions=tuple(b.direction for b in parameters.bends),
    )

    # Bend table з двома рядками.
    _draw_z_bracket_bend_table(c, parameters, unfolded, origin_mm=(175, 170))

    # BOM через generic — auto-layout під таблицею (2 гиби → нижче).
    _draw_bom_block(
        c,
        material_label=material_label,
        thickness_mm=unfolded.thickness_mm,
        bom=compute_bom(unfolded, density_kg_m3=density_kg_m3),
        origin_mm=_choose_bom_origin(2),
    )
    if solid is not None:
        _draw_isometric(c, solid, parameters, unfolded)

    # QR-код.
    qr_png = _make_qr_png(qr_payload)
    qr_size_mm = 30
    qr_buf = io.BytesIO(qr_png)
    c.drawImage(
        _ImageReader(qr_buf),
        (PAGE_WIDTH / mm - qr_size_mm - 15) * mm,
        15 * mm,
        width=qr_size_mm * mm,
        height=qr_size_mm * mm,
    )
    c.setFont("DejaVuSans", 7)
    c.drawString(
        (PAGE_WIDTH / mm - qr_size_mm - 15) * mm,
        12 * mm,
        f"QR: {qr_payload[:48]}",
    )

    c.setFont("DejaVuSans-Oblique", 8)
    c.drawString(
        15 * mm,
        15 * mm,
        "DXF для лазерного різання · BEND-LINES = лінії гибу (не різати)",
    )

    _draw_beta_watermark(c, PAGE_WIDTH, PAGE_HEIGHT)
    c.showPage()
    c.save()
    _normalize_pdf_bytes(output_path)
    return output_path


def export_corner_angle_pdf(
    parameters: CornerAngleBuildParameters,
    unfolded: UnfoldedCornerAngle,
    output_path: Path,
    *,
    solid: cq.Workplane | None = None,
    material_label: str = "cold_rolled_steel",
    density_kg_m3: float = 7850.0,
    permalink_url: str | None = None,
) -> Path:
    """PDF для corner_angle: 1 bend + grid отворів + bend table + BOM + QR."""
    article = (
        hashlib.sha256(json.dumps(parameters.model_dump(), sort_keys=True).encode("utf-8"))
        .hexdigest()[:10]
        .upper()
    )
    qr_payload = permalink_url or f"flatcraft://corner_angle/{article}"

    c = pdfcanvas.Canvas(str(output_path), pagesize=landscape(A4))
    c.setTitle(f"Corner angle {article}")
    c.setAuthor("flatcraft")
    c.setCreator("flatcraft-cad-worker")
    c.setProducer("flatcraft-cad-worker")
    c.setSubject(
        f"Corner angle {parameters.leg_a_mm}×{parameters.leg_b_mm}×{parameters.width_mm} мм",
    )

    c.setFont("DejaVuSans-Bold", 14)
    c.drawString(15 * mm, (210 - 15) * mm, "Кутник")
    c.setFont("DejaVuSans", 10)
    today = datetime.now(UTC).strftime("%Y-%m-%d")
    c.drawString(
        15 * mm,
        (210 - 20) * mm,
        f"slug: corner_angle · артикул: {article} · дата: {today}",
    )
    n_holes = len(unfolded.holes)
    c.drawString(
        15 * mm,
        (210 - 24) * mm,
        f"A={parameters.leg_a_mm} · B={parameters.leg_b_mm} · W={parameters.width_mm} мм · "
        f"R={parameters.bend_radius_mm} мм · "
        f"отвори: {parameters.hole_rows}×{parameters.hole_cols}×2 (всього {n_holes}, "
        f"Ø{parameters.hole_diameter_mm:g} мм)",
    )
    _draw_finished_dims_line(c, "corner_angle", parameters)

    _draw_unfold_generic(
        c,
        length_mm=unfolded.length_mm,
        width_mm=unfolded.width_mm,
        bend_positions_mm=(unfolded.bend_position_mm,),
        origin_mm=(15, 70),
        canvas_size_mm=(150, 100),
        holes=unfolded.holes,
        bend_radius_mm=parameters.bend_radius_mm,
        bend_directions=(parameters.bend_direction,),
    )

    # Bend table (1 рядок).
    _draw_bend_table_rows(
        c,
        [
            (
                "1",
                f"{parameters.bend_angle_deg}",
                f"{parameters.bend_radius_mm}",
                f"{parameters.width_mm:.1f}",
                "0.40",
                f"{unfolded.bend_allowance_mm:.2f}",
                _direction_label(parameters.bend_direction),
            )
        ],
        origin_mm=(175, 170),
    )

    # BOM через generic — auto-layout під таблицею (1 гиб).
    _draw_bom_block(
        c,
        material_label=material_label,
        thickness_mm=unfolded.thickness_mm,
        bom=compute_bom(unfolded, density_kg_m3=density_kg_m3),
        origin_mm=_choose_bom_origin(1),
    )
    if solid is not None:
        _draw_isometric(c, solid, parameters, unfolded)

    # QR.
    qr_png = _make_qr_png(qr_payload)
    qr_size_mm = 30
    qr_buf = io.BytesIO(qr_png)
    c.drawImage(
        _ImageReader(qr_buf),
        (PAGE_WIDTH / mm - qr_size_mm - 15) * mm,
        15 * mm,
        width=qr_size_mm * mm,
        height=qr_size_mm * mm,
    )
    c.setFont("DejaVuSans", 7)
    c.drawString(
        (PAGE_WIDTH / mm - qr_size_mm - 15) * mm,
        12 * mm,
        f"QR: {qr_payload[:48]}",
    )

    c.setFont("DejaVuSans-Oblique", 8)
    c.drawString(
        15 * mm,
        15 * mm,
        "DXF для лазерного різання · BEND-LINE = лінія гиба · INNER_CUTS = отвори",
    )

    _draw_beta_watermark(c, PAGE_WIDTH, PAGE_HEIGHT)
    c.showPage()
    c.save()
    _normalize_pdf_bytes(output_path)
    return output_path


def export_wall_shelf_pdf(
    parameters: WallShelfBuildParameters,
    unfolded: UnfoldedWallShelf,
    output_path: Path,
    *,
    solid: cq.Workplane | None = None,
    material_label: str = "cold_rolled_steel",
    density_kg_m3: float = 7850.0,
    permalink_url: str | None = None,
) -> Path:
    """PDF для wall_shelf U-channel: 1-2 bends + mount holes + bend table + BOM + QR."""
    article = (
        hashlib.sha256(json.dumps(parameters.model_dump(), sort_keys=True).encode("utf-8"))
        .hexdigest()[:10]
        .upper()
    )
    qr_payload = permalink_url or f"flatcraft://wall_shelf/{article}"
    n_bends = len(unfolded.bend_positions_mm)
    n_holes = len(unfolded.holes)

    c = pdfcanvas.Canvas(str(output_path), pagesize=landscape(A4))
    c.setTitle(f"Wall shelf {article}")
    c.setAuthor("flatcraft")
    c.setCreator("flatcraft-cad-worker")
    c.setProducer("flatcraft-cad-worker")
    c.setSubject(
        f"Wall shelf back={parameters.back_height_mm} shelf={parameters.shelf_depth_mm} "
        f"lip={parameters.front_lip_mm} W={parameters.width_mm} мм"
    )

    c.setFont("DejaVuSans-Bold", 14)
    c.drawString(15 * mm, (210 - 15) * mm, "Полиця настінна")
    c.setFont("DejaVuSans", 10)
    today = datetime.now(UTC).strftime("%Y-%m-%d")
    c.drawString(
        15 * mm,
        (210 - 20) * mm,
        f"slug: wall_shelf · артикул: {article} · дата: {today}",
    )
    c.drawString(
        15 * mm,
        (210 - 24) * mm,
        f"back={parameters.back_height_mm} · shelf={parameters.shelf_depth_mm} · "
        f"lip={parameters.front_lip_mm} мм · W={parameters.width_mm} мм · "
        f"гибів: {n_bends} · отворів: {n_holes} (Ø{parameters.mount_hole_diameter_mm:g})",
    )
    _draw_finished_dims_line(c, "wall_shelf", parameters)

    _draw_unfold_generic(
        c,
        length_mm=unfolded.length_mm,
        width_mm=unfolded.width_mm,
        bend_positions_mm=unfolded.bend_positions_mm,
        origin_mm=(15, 70),
        canvas_size_mm=(150, 100),
        holes=unfolded.holes,
        bend_radius_mm=parameters.bend_radius_mm,
        bend_directions=tuple(b.direction for b in parameters.bends),
    )

    # Bend table (1 або 2 рядки).
    body_rows: list[tuple[str, ...]] = [
        (
            str(i + 1),
            f"{parameters.bend_angle_deg}",
            f"{parameters.bend_radius_mm}",
            f"{parameters.width_mm:.1f}",
            "0.40",
            f"{unfolded.bend_allowance_mm:.2f}",
            _direction_label(
                parameters.bends[i].direction if i < len(parameters.bends) else "down"
            ),
        )
        for i in range(n_bends)
    ]
    _draw_bend_table_rows(c, body_rows, origin_mm=(175, 170))

    # BOM — auto-layout під таблицею (1-2 гиби залежно від front_lip).
    _draw_bom_block(
        c,
        material_label=material_label,
        thickness_mm=unfolded.thickness_mm,
        bom=compute_bom(unfolded, density_kg_m3=density_kg_m3),
        origin_mm=_choose_bom_origin(n_bends),
    )
    if solid is not None:
        _draw_isometric(c, solid, parameters, unfolded)

    qr_png = _make_qr_png(qr_payload)
    qr_size_mm = 30
    qr_buf = io.BytesIO(qr_png)
    c.drawImage(
        _ImageReader(qr_buf),
        (PAGE_WIDTH / mm - qr_size_mm - 15) * mm,
        15 * mm,
        width=qr_size_mm * mm,
        height=qr_size_mm * mm,
    )
    c.setFont("DejaVuSans", 7)
    c.drawString(
        (PAGE_WIDTH / mm - qr_size_mm - 15) * mm,
        12 * mm,
        f"QR: {qr_payload[:48]}",
    )

    c.setFont("DejaVuSans-Oblique", 8)
    c.drawString(
        15 * mm,
        15 * mm,
        "DXF для лазерного різання · BEND-LINES = гиби · INNER_CUTS = mounting holes",
    )

    _draw_beta_watermark(c, PAGE_WIDTH, PAGE_HEIGHT)
    c.showPage()
    c.save()
    _normalize_pdf_bytes(output_path)
    return output_path


def export_perforated_panel_pdf(
    parameters: PerforatedPanelBuildParameters,
    unfolded: UnfoldedPerforatedPanel,
    output_path: Path,
    *,
    solid: cq.Workplane | None = None,
    material_label: str = "cold_rolled_steel",
    density_kg_m3: float = 7850.0,
    permalink_url: str | None = None,
) -> Path:
    """PDF для perforated_panel: rectangle + hole grid + BOM + QR (без bend table)."""
    article = (
        hashlib.sha256(json.dumps(parameters.model_dump(), sort_keys=True).encode("utf-8"))
        .hexdigest()[:10]
        .upper()
    )
    qr_payload = permalink_url or f"flatcraft://perforated_panel/{article}"
    n_holes = len(unfolded.holes)

    c = pdfcanvas.Canvas(str(output_path), pagesize=landscape(A4))
    c.setTitle(f"Perforated panel {article}")
    c.setAuthor("flatcraft")
    c.setCreator("flatcraft-cad-worker")
    c.setProducer("flatcraft-cad-worker")
    c.setSubject(
        f"Perforated panel {parameters.length_mm}×{parameters.width_mm} мм, "
        f"{n_holes} holes Ø{parameters.hole_diameter_mm}"
    )

    c.setFont("DejaVuSans-Bold", 14)
    c.drawString(15 * mm, (210 - 15) * mm, "Перфо-панель")
    c.setFont("DejaVuSans", 10)
    today = datetime.now(UTC).strftime("%Y-%m-%d")
    c.drawString(
        15 * mm,
        (210 - 20) * mm,
        f"slug: perforated_panel · артикул: {article} · дата: {today}",
    )
    c.drawString(
        15 * mm,
        (210 - 24) * mm,
        f"Лист {parameters.length_mm}×{parameters.width_mm} мм · крок "
        f"pitch_x={parameters.pitch_x_mm} pitch_y={parameters.pitch_y_mm} · "
        f"grid {unfolded.grid_cols}×{unfolded.grid_rows} = {n_holes} отворів "
        f"Ø{parameters.hole_diameter_mm:g} мм",
    )
    _draw_finished_dims_line(c, "perforated_panel", parameters)

    _draw_unfold_generic(
        c,
        length_mm=unfolded.length_mm,
        width_mm=unfolded.width_mm,
        bend_positions_mm=(),
        origin_mm=(15, 70),
        canvas_size_mm=(150, 100),
        holes=unfolded.holes,
    )

    # PR 8c (issue #5): уніфікована таблиця «Розміри» (2 колонки) замість
    # неструктурованого текстового блоку. Той самий visual style, що bend-table.
    bottom_y = _draw_dimensions_table(
        c,
        "Розміри",
        [
            ("Довжина L, мм", f"{parameters.length_mm:g}"),
            ("Ширина W, мм", f"{parameters.width_mm:g}"),
            ("Товщина, мм", f"{unfolded.thickness_mm:g}"),
            ("Діаметр отвору Ø, мм", f"{parameters.hole_diameter_mm:g}"),
            ("Pitch X, мм", f"{parameters.pitch_x_mm:g}"),
            ("Pitch Y, мм", f"{parameters.pitch_y_mm:g}"),
            ("Відступ від країв, мм", f"{parameters.margin_mm:g}"),
            ("Сітка (cols×rows)", f"{unfolded.grid_cols}×{unfolded.grid_rows} = {n_holes}"),
        ],
        origin_mm=(175, 170),
    )

    # BOM під таблицею розмірів (auto-position з відступом 6мм).
    _draw_bom_block(
        c,
        material_label=material_label,
        thickness_mm=unfolded.thickness_mm,
        bom=compute_bom(unfolded, density_kg_m3=density_kg_m3),
        origin_mm=(175, bottom_y - 6),
        include_volume=False,
    )
    if solid is not None:
        _draw_isometric(c, solid, parameters, unfolded)

    qr_png = _make_qr_png(qr_payload)
    qr_size_mm = 30
    qr_buf = io.BytesIO(qr_png)
    c.drawImage(
        _ImageReader(qr_buf),
        (PAGE_WIDTH / mm - qr_size_mm - 15) * mm,
        15 * mm,
        width=qr_size_mm * mm,
        height=qr_size_mm * mm,
    )
    c.setFont("DejaVuSans", 7)
    c.drawString(
        (PAGE_WIDTH / mm - qr_size_mm - 15) * mm,
        12 * mm,
        f"QR: {qr_payload[:48]}",
    )

    c.setFont("DejaVuSans-Oblique", 8)
    c.drawString(
        15 * mm,
        15 * mm,
        "DXF для лазерного різання · INNER_CUTS = отвори · BEND операцій немає",
    )

    _draw_beta_watermark(c, PAGE_WIDTH, PAGE_HEIGHT)
    c.showPage()
    c.save()
    _normalize_pdf_bytes(output_path)
    return output_path


def _draw_unfold_perfo_ribbed(
    c: pdfcanvas.Canvas,
    unfolded: UnfoldedPerforatedPanelSquare,
    *,
    origin_mm: tuple[float, float],
    canvas_size_mm: tuple[float, float],
) -> None:
    """Малює cross-розгортку ребристого лотка (ADR-030).

    Контур (з R5 на вільних кутах ребер) + 4 bend lines (dashed) + перфорація
    (square, blue) + 4 установочні отвори Ø5.5 (red) + кріпильні розміри
    (bolt pattern + підписи між центрами отворів).
    """
    ox_mm, oy_mm = origin_mm
    canvas_w, canvas_h = canvas_size_mm
    bbox_w = unfolded.bbox_max_x_mm - unfolded.bbox_min_x_mm
    bbox_h = unfolded.bbox_max_y_mm - unfolded.bbox_min_y_mm
    scale = min(canvas_w / max(bbox_w, 1), canvas_h / max(bbox_h, 1))
    x0_mm = ox_mm + (canvas_w - bbox_w * scale) / 2.0
    y0_mm = oy_mm + (canvas_h - bbox_h * scale) / 2.0

    def _to_pt(xm: float, ym: float) -> tuple[float, float]:
        return (
            (x0_mm + (xm - unfolded.bbox_min_x_mm) * scale) * mm,
            (y0_mm + (ym - unfolded.bbox_min_y_mm) * scale) * mm,
        )

    # Cross-outline (black solid) — щільні вершини несуть R5-дуги.
    c.setLineWidth(1.0)
    c.setStrokeColorRGB(0, 0, 0)
    path = c.beginPath()
    px, py = _to_pt(*unfolded.outline_vertices[0])
    path.moveTo(px, py)
    for vx, vy in unfolded.outline_vertices[1:]:
        px, py = _to_pt(vx, vy)
        path.lineTo(px, py)
    path.close()
    c.drawPath(path, stroke=1, fill=0)

    # Лінії гибу — dashed blue.
    c.saveState()
    c.setDash(4, 3)
    c.setStrokeColorRGB(0.2, 0.4, 0.8)
    c.setLineWidth(0.6)
    for bend in unfolded.bend_lines:
        x1, y1 = _to_pt(bend.x1_mm, bend.y1_mm)
        x2, y2 = _to_pt(bend.x2_mm, bend.y2_mm)
        c.line(x1, y1, x2, y2)
    c.restoreState()

    # Перфорація — square, blue outline.
    c.saveState()
    c.setStrokeColorRGB(0.2, 0.4, 0.8)
    c.setLineWidth(0.3)
    for hole in unfolded.holes:
        cx, cy = _to_pt(hole.x_mm, hole.y_mm)
        half_pt = (hole.diameter_mm / 2.0) * scale * mm
        c.rect(cx - half_pt, cy - half_pt, 2 * half_pt, 2 * half_pt, stroke=1, fill=0)
    c.restoreState()

    # Установочні отвори Ø5.5 — red circles.
    c.saveState()
    c.setStrokeColorRGB(0.8, 0.1, 0.1)
    c.setLineWidth(0.6)
    for hole in unfolded.corner_holes:
        cx, cy = _to_pt(hole.x_mm, hole.y_mm)
        c.circle(cx, cy, (hole.diameter_mm / 2.0) * scale * mm, stroke=1, fill=0)
    c.restoreState()

    # Кріпильні розміри (bolt pattern) між центрами 4 кутових отворів.
    if len(unfolded.corner_holes) == 4:
        bl, br, tl, tr = unfolded.corner_holes  # BL, BR, TL, TR
        c.saveState()
        c.setStrokeColorRGB(0.63, 0.38, 0.0)
        c.setLineWidth(0.4)
        rect_path = c.beginPath()
        rx, ry = _to_pt(bl.x_mm, bl.y_mm)
        rect_path.moveTo(rx, ry)
        for pt in (br, tr, tl, bl):
            rx, ry = _to_pt(pt.x_mm, pt.y_mm)
            rect_path.lineTo(rx, ry)
        c.drawPath(rect_path, stroke=1, fill=0)
        c.setFillColorRGB(0.63, 0.38, 0.0)
        c.setFont("DejaVuSans", 7)
        tlx, tly = _to_pt(tl.x_mm, tl.y_mm)
        trx, _ = _to_pt(tr.x_mm, tr.y_mm)
        c.drawCentredString((tlx + trx) / 2, tly + 2, f"{br.x_mm - bl.x_mm:g}")
        blx, bly = _to_pt(bl.x_mm, bl.y_mm)
        c.saveState()
        c.translate(blx - 2, (bly + tly) / 2)
        c.rotate(90)
        c.drawCentredString(0, 0, f"{tl.y_mm - bl.y_mm:g}")
        c.restoreState()
        c.restoreState()


def export_perforated_panel_square_pdf(
    parameters: PerforatedPanelSquareBuildParameters,
    unfolded: UnfoldedPerforatedPanelSquare,
    output_path: Path,
    *,
    solid: cq.Workplane | None = None,
    material_label: str = "cold_rolled_steel",
    density_kg_m3: float = 7850.0,
    permalink_url: str | None = None,
) -> Path:
    """PDF для перфо-монтажної панелі (ребриста, ADR-030).

    Cross-розгортка лотка (R5 на кутах ребер) + 4 bend lines + уніфікована
    таблиця «Розміри» (вкл. ребро/гиб/кріпильні розміри) + BOM + QR. Без
    isometric view (як enclosed_shelf — інший гнутий лоток). `solid` приймається
    для сумісності сигнатури, але isometric тут не рендериться.
    """
    _ = solid
    article = (
        hashlib.sha256(json.dumps(parameters.model_dump(), sort_keys=True).encode("utf-8"))
        .hexdigest()[:10]
        .upper()
    )
    qr_payload = permalink_url or f"flatcraft://perforated_panel_square/{article}"
    n_holes = len(unfolded.holes)

    c = pdfcanvas.Canvas(str(output_path), pagesize=landscape(A4))
    c.setTitle(f"Perforated panel square {article}")
    c.setAuthor("flatcraft")
    c.setCreator("flatcraft-cad-worker")
    c.setProducer("flatcraft-cad-worker")
    c.setSubject(
        f"Perforated panel square {parameters.length_mm}×{parameters.width_mm} мм, "
        f"{n_holes} square holes □{parameters.hole_size_mm}"
    )

    c.setFont("DejaVuSans-Bold", 14)
    c.drawString(15 * mm, (210 - 15) * mm, "Перфо-монтажна панель (ребриста)")
    c.setFont("DejaVuSans", 10)
    today = datetime.now(UTC).strftime("%Y-%m-%d")
    c.drawString(
        15 * mm,
        (210 - 20) * mm,
        f"slug: perforated_panel_square · артикул: {article} · дата: {today}",
    )
    c.drawString(
        15 * mm,
        (210 - 24) * mm,
        f"Площина {parameters.length_mm:g}×{parameters.width_mm:g} мм · 4 ребра "
        f"h={parameters.rib_height_mm:g}мм (R{parameters.rib_corner_radius_mm:g}) · "
        f"grid {unfolded.grid_cols}×{unfolded.grid_rows} = {n_holes} отв "
        f"□{parameters.hole_size_mm:g} · 4× Ø{CORNER_HOLE_DIAMETER_MM:g}",
    )
    # _draw_finished_dims_line dispatch'ує за slug; підтримка нового шаблону
    # додана у dimensions.compute_finished_dimensions (той самий X×Y×Z).
    _draw_finished_dims_line(c, "perforated_panel_square", parameters)

    _draw_unfold_perfo_ribbed(
        c,
        unfolded,
        origin_mm=(15, 70),
        canvas_size_mm=(150, 100),
    )

    # Кріпильні розміри (bolt pattern) + габарит заготовки.
    ins = parameters.corner_hole_inset_mm
    mount_x = parameters.length_mm - 2 * ins
    mount_y = parameters.width_mm - 2 * ins
    blank_w = unfolded.bbox_max_x_mm - unfolded.bbox_min_x_mm
    blank_h = unfolded.bbox_max_y_mm - unfolded.bbox_min_y_mm

    # Уніфікована таблиця «Розміри» — вкл. ребро/гиб/кріпильні розміри.
    bottom_y = _draw_dimensions_table(
        c,
        "Розміри",
        [
            ("Площина L×W, мм", f"{parameters.length_mm:g}×{parameters.width_mm:g}"),
            ("Товщина, мм", f"{unfolded.thickness_mm:g}"),
            ("Сторона отвору □, мм", f"{parameters.hole_size_mm:g}"),
            ("Крок X×Y, мм", f"{parameters.pitch_x_mm:g}×{parameters.pitch_y_mm:g}"),
            ("Відступ від країв, мм", f"{parameters.margin_mm:g}"),
            ("Сітка (cols×rows)", f"{unfolded.grid_cols}×{unfolded.grid_rows} = {n_holes}"),
            ("Ребро h, мм", f"{parameters.rib_height_mm:g}"),
            ("Гиб R / кут", f"{parameters.bend_radius_mm:g} / 90°"),
            ("BA / напрям", f"{unfolded.bend_allowance_mm:.2f} / DOWN"),
            ("Скруглення ребра R, мм", f"{parameters.rib_corner_radius_mm:g}"),
            (f"Кріпильні Ø{CORNER_HOLE_DIAMETER_MM:g}, мм", f"{mount_x:g}×{mount_y:g}"),
            ("Заготовка, мм", f"{blank_w:.0f}×{blank_h:.0f}"),
        ],
        origin_mm=(175, 170),
    )

    # BOM з площею cross-заготовки (площина + 4 фланці), не лише площини.
    arm = unfolded.bend_allowance_mm + unfolded.flat_flange_mm
    area_mm2 = (
        parameters.length_mm * parameters.width_mm
        + 2 * (parameters.length_mm + parameters.width_mm) * arm
    )
    volume_m3 = (area_mm2 * unfolded.thickness_mm) / 1e9
    mass_kg = volume_m3 * density_kg_m3
    bom = {
        "area_mm2": area_mm2,
        "area_m2": area_mm2 / 1e6,
        "area_paint_m2": (area_mm2 / 1e6) * 2.0,
        "volume_m3": volume_m3,
        "mass_g": mass_kg * 1000.0,
        "mass_kg": mass_kg,
    }
    _draw_bom_block(
        c,
        material_label=material_label,
        thickness_mm=unfolded.thickness_mm,
        bom=bom,
        origin_mm=(175, bottom_y - 6),
        include_volume=False,
    )

    qr_png = _make_qr_png(qr_payload)
    qr_size_mm = 30
    qr_buf = io.BytesIO(qr_png)
    c.drawImage(
        _ImageReader(qr_buf),
        (PAGE_WIDTH / mm - qr_size_mm - 15) * mm,
        15 * mm,
        width=qr_size_mm * mm,
        height=qr_size_mm * mm,
    )
    c.setFont("DejaVuSans", 7)
    c.drawString(
        (PAGE_WIDTH / mm - qr_size_mm - 15) * mm,
        12 * mm,
        f"QR: {qr_payload[:48]}",
    )

    c.setFont("DejaVuSans-Oblique", 8)
    c.drawString(
        15 * mm,
        15 * mm,
        "DXF: cross-shape LASER_CUT (R-кути ребер) + 4 BEND_LINES (DOWN) · перфорація □ + 4× Ø5.5",
    )

    _draw_beta_watermark(c, PAGE_WIDTH, PAGE_HEIGHT)
    c.showPage()
    c.save()
    _normalize_pdf_bytes(output_path)
    return output_path


def _enclosed_shelf_area_mm2(unfolded: UnfoldedEnclosedShelf) -> float:
    """Сумарна площа сегментів cross-розгортки (без перетинів — сегменти не
    перекриваються у unfold)."""
    area = (
        unfolded.bottom.w_mm * unfolded.bottom.h_mm
        + unfolded.back.w_mm * unfolded.back.h_mm
        + unfolded.left.w_mm * unfolded.left.h_mm
        + unfolded.right.w_mm * unfolded.right.h_mm
    )
    if unfolded.rib is not None:
        area += unfolded.rib.w_mm * unfolded.rib.h_mm
    return area


def _draw_unfold_enclosed_shelf(
    c: pdfcanvas.Canvas,
    unfolded: UnfoldedEnclosedShelf,
    *,
    origin_mm: tuple[float, float],
    canvas_size_mm: tuple[float, float],
) -> None:
    """Малює cross-shape outline (LASER_CUT-аналог) + bend lines (BEND_LINES).

    Scaling: fit-to-canvas. Bend lines — dashed blue. Outline — solid black.
    """
    ox_mm, oy_mm = origin_mm
    canvas_w, canvas_h = canvas_size_mm
    bbox_w = unfolded.bbox_max_x_mm - unfolded.bbox_min_x_mm
    bbox_h = unfolded.bbox_max_y_mm - unfolded.bbox_min_y_mm
    scale = min(canvas_w / max(bbox_w, 1), canvas_h / max(bbox_h, 1))

    # Center the cross inside the canvas.
    w_drawn = bbox_w * scale
    h_drawn = bbox_h * scale
    x0_mm = ox_mm + (canvas_w - w_drawn) / 2.0
    y0_mm = oy_mm + (canvas_h - h_drawn) / 2.0

    def _to_pt(x_model: float, y_model: float) -> tuple[float, float]:
        x_pt = (x0_mm + (x_model - unfolded.bbox_min_x_mm) * scale) * mm
        y_pt = (y0_mm + (y_model - unfolded.bbox_min_y_mm) * scale) * mm
        return x_pt, y_pt

    # Outline — black solid.
    c.setLineWidth(1.0)
    c.setStrokeColorRGB(0, 0, 0)
    path = c.beginPath()
    first = unfolded.outline_vertices[0]
    px, py = _to_pt(*first)
    path.moveTo(px, py)
    for vx, vy in unfolded.outline_vertices[1:]:
        px, py = _to_pt(vx, vy)
        path.lineTo(px, py)
    path.close()
    c.drawPath(path, stroke=1, fill=0)

    # Bend lines — dashed blue.
    c.saveState()
    c.setDash(4, 3)
    c.setStrokeColorRGB(0.2, 0.4, 0.8)
    c.setLineWidth(0.6)
    for bend in unfolded.bend_lines:
        x1, y1 = _to_pt(bend.x1_mm, bend.y1_mm)
        x2, y2 = _to_pt(bend.x2_mm, bend.y2_mm)
        c.line(x1, y1, x2, y2)
    c.restoreState()

    # Side perforation holes — red circles/squares (наочно у PDF, у DXF — color 5).
    if unfolded.side_holes:
        c.saveState()
        c.setStrokeColorRGB(0.8, 0.2, 0.2)
        c.setLineWidth(0.4)
        for hole in unfolded.side_holes:
            cx, cy = _to_pt(hole.x_mm, hole.y_mm)
            half_pt = (hole.diameter_mm / 2.0) * scale * mm
            if hole.shape == "square":
                c.rect(cx - half_pt, cy - half_pt, 2 * half_pt, 2 * half_pt, stroke=1, fill=0)
            else:
                c.circle(cx, cy, half_pt, stroke=1, fill=0)
        c.restoreState()


def export_enclosed_shelf_pdf(
    parameters: EnclosedShelfBuildParameters,
    unfolded: UnfoldedEnclosedShelf,
    output_path: Path,
    *,
    material_label: str = "cold_rolled_steel",
    density_kg_m3: float = 7850.0,
    permalink_url: str | None = None,
) -> Path:
    """PDF для enclosed_shelf (Phase 3.0 PR 7c, ADR-027).

    Simplified-варіант MVP — БЕЗ isometric view (additional PR). Має:
    - Header: назва, slug, article, дата, dimensions.
    - Cross outline + bend lines (dashed).
    - Bend table (3-4 рядки).
    - BOM з сумарною площею сегментів.
    - Footer: QR + BETA watermark.
    """
    article = (
        hashlib.sha256(json.dumps(parameters.model_dump(), sort_keys=True).encode("utf-8"))
        .hexdigest()[:10]
        .upper()
    )
    qr_payload = permalink_url or f"flatcraft://enclosed_shelf/{article}"

    c = pdfcanvas.Canvas(str(output_path), pagesize=landscape(A4))
    c.setTitle(f"Enclosed shelf {article}")
    c.setAuthor("flatcraft")
    c.setCreator("flatcraft-cad-worker")
    c.setProducer("flatcraft-cad-worker")
    c.setSubject(
        f"Enclosed shelf {parameters.width_mm}×{parameters.depth_mm} мм, "
        f"{'4' if parameters.stiffening_rib is not None else '3'} bends"
    )

    c.setFont("DejaVuSans-Bold", 14)
    c.drawString(15 * mm, (210 - 15) * mm, "Закрита полиця (cross-розгортка)")
    c.setFont("DejaVuSans", 10)
    today = datetime.now(UTC).strftime("%Y-%m-%d")
    c.drawString(
        15 * mm,
        (210 - 20) * mm,
        f"slug: enclosed_shelf · артикул: {article} · дата: {today}",
    )
    rib_label = (
        f"+ ребро {parameters.stiffening_rib.height_mm:g}мм"
        if parameters.stiffening_rib is not None
        else "без ребра"
    )
    perf_label = "+ перфорація сторін" if parameters.side_perforation is not None else ""
    c.drawString(
        15 * mm,
        (210 - 24) * mm,
        f"{parameters.width_mm:g}×{parameters.depth_mm:g} мм · {rib_label} {perf_label}".rstrip(),
    )
    _draw_finished_dims_line(c, "enclosed_shelf", parameters)

    # Cross розгортка у лівій колонці.
    _draw_unfold_enclosed_shelf(
        c,
        unfolded,
        origin_mm=(15, 70),
        canvas_size_mm=(150, 100),
    )

    # PR 8c (issue #5): уніфікована таблиця «Розміри» (як у perfo-панелях).
    n_bends = len(unfolded.bend_lines)
    bend_descriptors = ["back", "left", "right", "rib"][:n_bends]
    k_derived = unfolded.bend_allowance_mm / (
        math.radians(90) * (parameters.bend_radius_mm + 0.4 * unfolded.thickness_mm)
    )
    bottom_y = _draw_dimensions_table(
        c,
        "Розміри",
        [
            ("Ширина W, мм", f"{parameters.width_mm:g}"),
            ("Глибина D, мм", f"{parameters.depth_mm:g}"),
            ("Товщина, мм", f"{unfolded.thickness_mm:g}"),
            ("Радіус гибу R, мм", f"{parameters.bend_radius_mm:g}"),
            ("Кут гибу, °", "90"),
            ("BA, мм", f"{unfolded.bend_allowance_mm:.2f}"),
            ("k-фактор (derived)", f"{k_derived:.2g}"),
            ("Напрям", "UP (усі)"),
            ("Гибів", f"{n_bends} ({', '.join(bend_descriptors)})"),
        ],
        origin_mm=(175, 170),
    )

    # BOM (custom — sum segment areas).
    area_mm2 = _enclosed_shelf_area_mm2(unfolded)
    area_m2 = area_mm2 / 1e6
    volume_m3 = (area_mm2 * unfolded.thickness_mm) / 1e9
    mass_kg = volume_m3 * density_kg_m3
    bom = {
        "area_mm2": area_mm2,
        "area_m2": area_m2,
        "area_paint_m2": area_m2 * 2.0,
        "volume_m3": volume_m3,
        "mass_g": mass_kg * 1000.0,
        "mass_kg": mass_kg,
    }
    _draw_bom_block(
        c,
        material_label=material_label,
        thickness_mm=unfolded.thickness_mm,
        bom=bom,
        origin_mm=(175, bottom_y - 6),
        include_volume=False,
    )

    qr_png = _make_qr_png(qr_payload)
    qr_size_mm = 30
    qr_buf = io.BytesIO(qr_png)
    c.drawImage(
        _ImageReader(qr_buf),
        (PAGE_WIDTH / mm - qr_size_mm - 15) * mm,
        15 * mm,
        width=qr_size_mm * mm,
        height=qr_size_mm * mm,
    )
    c.setFont("DejaVuSans", 7)
    c.drawString(
        (PAGE_WIDTH / mm - qr_size_mm - 15) * mm,
        12 * mm,
        f"QR: {qr_payload[:48]}",
    )

    c.setFont("DejaVuSans-Oblique", 8)
    c.drawString(
        15 * mm,
        15 * mm,
        "DXF: cross-shape LASER_CUT + 3-4 BEND_LINES (UP) · опц. перфорація сторін",
    )

    _draw_beta_watermark(c, PAGE_WIDTH, PAGE_HEIGHT)
    c.showPage()
    c.save()
    _normalize_pdf_bytes(output_path)
    return output_path


def _draw_unfold_generic(
    c: pdfcanvas.Canvas,
    *,
    length_mm: float,
    width_mm: float,
    bend_positions_mm: tuple[float, ...],
    origin_mm: tuple[float, float],
    canvas_size_mm: tuple[float, float],
    holes: tuple[Hole2D, ...] = (),
    bend_radius_mm: float = 0.0,
    bend_directions: tuple[str, ...] = (),
) -> None:
    """Generic-варіант _draw_unfold для довільної кількості bend lines і отворів.

    Callout кожного гибу: `BEND #{n} {arrow} R{radius} d={distance}мм`.
    Overlap-fix: якщо два callouts ближче за 30мм по X (model space) — другий
    зсувається на +12pt по Y, щоб не накладались.
    """
    ox_mm, oy_mm = origin_mm
    canvas_w, canvas_h = canvas_size_mm
    scale = min(canvas_w / max(length_mm, 1), canvas_h / max(width_mm, 1))
    w = length_mm * scale
    h = width_mm * scale

    x0 = (ox_mm + (canvas_w - w) / 2) * mm
    y0 = (oy_mm + (canvas_h - h) / 2) * mm

    c.setLineWidth(1.0)
    c.rect(x0, y0, w * mm, h * mm, stroke=1, fill=0)

    prev_pos_mm: float | None = None
    for n, bend_mm in enumerate(bend_positions_mm):
        bend_x = bend_mm * scale
        direction = bend_directions[n] if n < len(bend_directions) else "down"
        c.saveState()
        c.setDash(4, 3)
        c.setStrokeColorRGB(0.2, 0.4, 0.8)
        c.line(x0 + bend_x * mm, y0, x0 + bend_x * mm, y0 + h * mm)
        c.restoreState()
        # Overlap-fix: callouts ближче за 30мм по X → зсув +12pt по Y.
        extra_y = 12.0 if prev_pos_mm is not None and (bend_mm - prev_pos_mm) < 30.0 else 0.0
        c.setFillColorRGB(0.2, 0.4, 0.8)
        c.setFont("DejaVuSans", 7)
        c.drawCentredString(
            x0 + bend_x * mm,
            y0 + h * mm + 2 * mm + extra_y,
            f"BEND #{n + 1} {_direction_label(direction)} R{bend_radius_mm:g} d={bend_mm:.1f}мм",
        )
        c.setFillColorRGB(0, 0, 0)
        prev_pos_mm = bend_mm

    # Bend number badges ПОСЕРЕДИНІ кожної лінії (Phase 2.9.b Block B).
    _draw_bend_badges(
        c,
        _bend_badges_for(bend_positions_mm, width_mm),
        x0_pt=x0,
        y0_pt=y0,
        scale=scale,
    )

    if holes:
        c.saveState()
        c.setStrokeColorRGB(0.8, 0.2, 0.2)
        c.setLineWidth(0.5)
        for hole in holes:
            cx = x0 + hole.x_mm * scale * mm
            cy = y0 + hole.y_mm * scale * mm
            # ADR-027 Рішення 6: shape='square' → rect (side=diameter_mm),
            # 'circle' → circle (diameter_mm/2 radius). PR 8a fix: до цього
            # _draw_unfold_generic завжди малював circle → square holes на
            # perforated_panel_square PDF виглядали як круги.
            half_pdf = (hole.diameter_mm / 2.0) * scale * mm
            if hole.shape == "square":
                c.rect(cx - half_pdf, cy - half_pdf, 2 * half_pdf, 2 * half_pdf, stroke=1, fill=0)
            else:
                c.circle(cx, cy, half_pdf, stroke=1, fill=0)
        c.restoreState()
        # □/Ø-callouts (Phase 2.9.b Block F): на кожен отвір (≤ cap) або один + «×N».
        _draw_hole_dims(c, holes, x0_pt=x0, y0_pt=y0, scale=scale, part_top_pt=y0 + h * mm)

    c.setFont("DejaVuSans", 8)
    c.drawCentredString(x0 + (w * mm) / 2, y0 - 4 * mm, f"L = {length_mm:.2f} мм")
    c.saveState()
    c.translate(x0 - 5 * mm, y0 + (h * mm) / 2)
    c.rotate(90)
    c.drawCentredString(0, 0, f"W = {width_mm:.2f} мм")
    c.restoreState()


def _draw_z_bracket_bend_table(
    c: pdfcanvas.Canvas,
    parameters: ZBracketBuildParameters,
    unfolded: UnfoldedZBracket,
    *,
    origin_mm: tuple[float, float],
) -> None:
    body_rows: list[tuple[str, ...]] = [
        (
            str(i + 1),
            f"{parameters.bend_angle_deg}",
            f"{parameters.bend_radius_mm}",
            f"{parameters.width_mm:.1f}",
            "0.40",
            f"{unfolded.bend_allowance_mm:.2f}",
            _direction_label(parameters.bends[i].direction),
        )
        for i in range(2)
    ]
    _draw_bend_table_rows(c, body_rows, origin_mm=origin_mm)


# ReportLab ImageReader лише для readability — окремий імпорт щоб mypy
# побачив тип.
from reportlab.lib.utils import ImageReader as _ImageReader  # noqa: E402
