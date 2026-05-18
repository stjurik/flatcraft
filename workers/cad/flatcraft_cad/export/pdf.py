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

Ізометрія 3D у Phase 2.9 поки не вкладена — ReportLab native 2D, повноцінний
WebGL→PNG render вимагає окремого pipeline'у (Phase post-MVP). Поточний
DXF (Phase 2.7) уже дає клієнтам відкривати у LibreCAD/FreeCAD для огляду.

Детермінізм (CLAUDE.md §2.4): однакові params → байт-у-байт ідентичний PDF.
ReportLab вставляє timestamp у metadata; постобробку timestamp/ID робимо
у `_normalize_pdf_bytes` як для DXF (Phase 1.8).
"""

from __future__ import annotations

import hashlib
import io
import json
import re
from datetime import UTC, datetime
from pathlib import Path
from typing import Final

import qrcode
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas as pdfcanvas

from flatcraft_cad.templates.l_bracket import LBracketBuildParameters
from flatcraft_cad.templates.z_bracket import ZBracketBuildParameters
from flatcraft_cad.unfold import UnfoldedLBracket, UnfoldedZBracket

PAGE_WIDTH, PAGE_HEIGHT = landscape(A4)


def compute_bom(
    unfolded: UnfoldedLBracket | UnfoldedZBracket,
    *,
    density_kg_m3: float = 7850.0,
) -> dict[str, float]:
    """Bill of materials для розгорнутого аркуша.

    Pure-функція, відокремлена від PDF-рендерингу — щоб числа можна
    було перевіряти юніт-тестами без парсингу PDF (Cyrillic у Helvetica
    PDF не екстрактується pypdf). Працює з будь-яким Unfolded* dataclass,
    що має length_mm/width_mm/thickness_mm fields (L, Z, U/wall_shelf).
    """
    area_mm2 = unfolded.length_mm * unfolded.width_mm
    volume_mm3 = area_mm2 * unfolded.thickness_mm
    return {
        "area_mm2": area_mm2,
        "area_m2": area_mm2 / 1e6,
        "volume_m3": volume_mm3 / 1e9,
        "mass_g": (volume_mm3 / 1e9) * density_kg_m3 * 1000.0,
    }


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

    # Annotations: length / width / bend position.
    c.setFont("Helvetica", 8)
    c.drawCentredString(x0 + (w * mm) / 2, y0 - 4 * mm, f"L = {unfolded.length_mm:.2f} мм")
    c.saveState()
    c.translate(x0 - 5 * mm, y0 + (h * mm) / 2)
    c.rotate(90)
    c.drawCentredString(0, 0, f"W = {unfolded.width_mm:.2f} мм")
    c.restoreState()
    c.setFillColorRGB(0.2, 0.4, 0.8)
    c.drawCentredString(
        x0 + bend_x * mm,
        y0 + h * mm + 2 * mm,
        f"BEND @ {unfolded.bend_position_mm:.2f} мм",
    )
    c.setFillColorRGB(0, 0, 0)


def _draw_bend_table(
    c: pdfcanvas.Canvas,
    parameters: LBracketBuildParameters,
    unfolded: UnfoldedLBracket,
    *,
    origin_mm: tuple[float, float],
) -> None:
    ox, oy = origin_mm
    c.setFont("Helvetica-Bold", 10)
    c.drawString(ox * mm, oy * mm, "Гиби")
    rows = [
        ("#", "Кут, °", "R вн., мм", "Довжина, мм", "K-фактор", "BA, мм"),
        (
            "1",
            f"{parameters.bend_angle_deg}",
            f"{parameters.bend_radius_mm}",
            f"{parameters.width_mm:.1f}",
            "0.40",
            f"{unfolded.bend_allowance_mm:.2f}",
        ),
    ]
    col_widths_mm = [10, 18, 22, 25, 22, 22]
    row_h_mm = 6
    cur_y_mm = oy - 7
    c.setLineWidth(0.4)
    for r_idx, row in enumerate(rows):
        cur_x_mm = ox
        if r_idx == 0:
            c.setFont("Helvetica-Bold", 8)
        else:
            c.setFont("Helvetica", 9)
        for cell, w_mm in zip(row, col_widths_mm, strict=True):
            c.rect(cur_x_mm * mm, cur_y_mm * mm, w_mm * mm, row_h_mm * mm, stroke=1, fill=0)
            c.drawString((cur_x_mm + 1) * mm, (cur_y_mm + 1.5) * mm, cell)
            cur_x_mm += w_mm
        cur_y_mm -= row_h_mm


def _draw_bom(
    c: pdfcanvas.Canvas,
    parameters: LBracketBuildParameters,
    unfolded: UnfoldedLBracket,
    *,
    material_label: str,
    density_kg_m3: float,
    origin_mm: tuple[float, float],
) -> None:
    ox, oy = origin_mm
    bom = compute_bom(unfolded, density_kg_m3=density_kg_m3)

    c.setFont("Helvetica-Bold", 10)
    c.drawString(ox * mm, oy * mm, "Bill of materials")
    c.setFont("Helvetica", 9)
    lines = [
        f"Матеріал: {material_label}",
        f"Товщина: {unfolded.thickness_mm:.2f} мм",
        f"Площа заготовки: {bom['area_m2']:.4f} м² ({bom['area_mm2']:.0f} мм²)",
        f"Об'єм: {bom['volume_m3']:.6f} м³",
        f"Маса (приблизно): {bom['mass_g']:.1f} г",
    ]
    for i, line in enumerate(lines):
        c.drawString(ox * mm, (oy - 4 - i * 4) * mm, line)


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
    c.setFont("Helvetica-Bold", 14)
    c.drawString(15 * mm, (210 - 15) * mm, "L-кронштейн")
    c.setFont("Helvetica", 10)
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

    # Layout.
    # Розгортка ліворуч (~150×110 мм), таблиці/BOM/QR праворуч.
    _draw_unfold(c, unfolded, origin_mm=(15, 70), canvas_size_mm=(150, 100))
    _draw_bend_table(c, parameters, unfolded, origin_mm=(175, 170))
    _draw_bom(
        c,
        parameters,
        unfolded,
        material_label=material_label,
        density_kg_m3=density_kg_m3,
        origin_mm=(175, 140),
    )

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
    c.setFont("Helvetica", 7)
    c.drawString(
        (PAGE_WIDTH / mm - qr_size_mm - 15) * mm,
        12 * mm,
        f"QR: {qr_payload[:48]}",
    )

    # Footer hint.
    c.setFont("Helvetica-Oblique", 8)
    c.drawString(
        15 * mm,
        15 * mm,
        "DXF для лазерного різання · BEND-LINES = лінія гиба (не різати)",
    )

    c.showPage()
    c.save()

    _normalize_pdf_bytes(output_path)
    return output_path


def export_z_bracket_pdf(
    parameters: ZBracketBuildParameters,
    unfolded: UnfoldedZBracket,
    output_path: Path,
    *,
    material_label: str = "cold_rolled_steel",
    density_kg_m3: float = 7850.0,
    permalink_url: str | None = None,
) -> Path:
    """PDF для Z-bracket: 2 паралельні bend lines + 2 рядки у bend table."""
    import hashlib
    import json

    article = hashlib.sha256(
        json.dumps(parameters.model_dump(), sort_keys=True).encode("utf-8")
    ).hexdigest()[:10].upper()
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

    c.setFont("Helvetica-Bold", 14)
    c.drawString(15 * mm, (210 - 15) * mm, "Z-кронштейн")
    c.setFont("Helvetica", 10)
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

    # Розгортка з двома bend lines.
    _draw_unfold_generic(
        c,
        length_mm=unfolded.length_mm,
        width_mm=unfolded.width_mm,
        bend_positions_mm=unfolded.bend_positions_mm,
        origin_mm=(15, 70),
        canvas_size_mm=(150, 100),
    )

    # Bend table з двома рядками.
    _draw_z_bracket_bend_table(c, parameters, unfolded, origin_mm=(175, 170))

    # BOM через generic.
    ox, oy = 175, 140
    bom = compute_bom(unfolded, density_kg_m3=density_kg_m3)
    c.setFont("Helvetica-Bold", 10)
    c.drawString(ox * mm, oy * mm, "Bill of materials")
    c.setFont("Helvetica", 9)
    for i, line in enumerate(
        [
            f"Матеріал: {material_label}",
            f"Товщина: {unfolded.thickness_mm:.2f} мм",
            f"Площа заготовки: {bom['area_m2']:.4f} м² ({bom['area_mm2']:.0f} мм²)",
            f"Об'єм: {bom['volume_m3']:.6f} м³",
            f"Маса (приблизно): {bom['mass_g']:.1f} г",
        ],
    ):
        c.drawString(ox * mm, (oy - 4 - i * 4) * mm, line)

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
    c.setFont("Helvetica", 7)
    c.drawString(
        (PAGE_WIDTH / mm - qr_size_mm - 15) * mm,
        12 * mm,
        f"QR: {qr_payload[:48]}",
    )

    c.setFont("Helvetica-Oblique", 8)
    c.drawString(
        15 * mm,
        15 * mm,
        "DXF для лазерного різання · BEND-LINES = лінії гибу (не різати)",
    )

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
) -> None:
    """Generic-варіант _draw_unfold для довільної кількості bend lines."""
    ox_mm, oy_mm = origin_mm
    canvas_w, canvas_h = canvas_size_mm
    scale = min(canvas_w / max(length_mm, 1), canvas_h / max(width_mm, 1))
    w = length_mm * scale
    h = width_mm * scale

    x0 = (ox_mm + (canvas_w - w) / 2) * mm
    y0 = (oy_mm + (canvas_h - h) / 2) * mm

    c.setLineWidth(1.0)
    c.rect(x0, y0, w * mm, h * mm, stroke=1, fill=0)

    for bend_mm in bend_positions_mm:
        bend_x = bend_mm * scale
        c.saveState()
        c.setDash(4, 3)
        c.setStrokeColorRGB(0.2, 0.4, 0.8)
        c.line(x0 + bend_x * mm, y0, x0 + bend_x * mm, y0 + h * mm)
        c.restoreState()
        c.setFillColorRGB(0.2, 0.4, 0.8)
        c.setFont("Helvetica", 7)
        c.drawCentredString(x0 + bend_x * mm, y0 + h * mm + 2 * mm, f"BEND @ {bend_mm:.1f}")
        c.setFillColorRGB(0, 0, 0)

    c.setFont("Helvetica", 8)
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
    ox, oy = origin_mm
    c.setFont("Helvetica-Bold", 10)
    c.drawString(ox * mm, oy * mm, "Гиби")
    rows = [
        ("#", "Кут, °", "R вн., мм", "Довжина, мм", "K-фактор", "BA, мм"),
        (
            "1",
            f"{parameters.bend_angle_deg}",
            f"{parameters.bend_radius_mm}",
            f"{parameters.width_mm:.1f}",
            "0.40",
            f"{unfolded.bend_allowance_mm:.2f}",
        ),
        (
            "2",
            f"{parameters.bend_angle_deg}",
            f"{parameters.bend_radius_mm}",
            f"{parameters.width_mm:.1f}",
            "0.40",
            f"{unfolded.bend_allowance_mm:.2f}",
        ),
    ]
    col_widths_mm = [10, 18, 22, 25, 22, 22]
    row_h_mm = 6
    cur_y_mm = oy - 7
    c.setLineWidth(0.4)
    for r_idx, row in enumerate(rows):
        cur_x_mm = ox
        if r_idx == 0:
            c.setFont("Helvetica-Bold", 8)
        else:
            c.setFont("Helvetica", 9)
        for cell, w_mm in zip(row, col_widths_mm, strict=True):
            c.rect(cur_x_mm * mm, cur_y_mm * mm, w_mm * mm, row_h_mm * mm, stroke=1, fill=0)
            c.drawString((cur_x_mm + 1) * mm, (cur_y_mm + 1.5) * mm, cell)
            cur_x_mm += w_mm
        cur_y_mm -= row_h_mm


# ReportLab ImageReader лише для readability — окремий імпорт щоб mypy
# побачив тип.
from reportlab.lib.utils import ImageReader as _ImageReader  # noqa: E402
