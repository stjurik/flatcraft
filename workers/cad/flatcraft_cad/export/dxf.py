"""DXF-експорт розгорнутих листометалевих виробів.

Production-grade структура для CAM (Lantek/SigmaNest/ESI) — ADR-024.
Рівно ДВА виробничі шари; жодного TEXT/DIMENSION (CAM-noise → ризик
вторсировини, бо CAM читав «LASER_CUT» як «усе, що ріжеться» і пропускав
отвори на окремому шарі):

- LASER_CUT (color 7): ВСІ cut-paths. Зовнішній контур — ByLayer (white);
  внутрішні вирізи (отвори) — той самий шар, але explicit color 5 (blue),
  щоб CAM/людина візуально відрізняли inner від outer (ByEntity color).
- BEND_LINES (color 3, dashed): лінії гибу (info, не ріжуться).

Текст/розміри/Ø-виноски/номери гибів лишаються ТІЛЬКИ у PDF — для людини,
не для CAM. Шар "0" обов'язковий за DXF-стандартом (ezdxf не дає видалити),
але лишається порожнім.

Детермінізм (CLAUDE.md §2.4): фіксуємо $TDCREATE/$TDUPDATE і GUID-и
з random-генерованих ezdxf-дефолтів. Це дає байт-у-байт identical
output для однакового вводу — обов'язково для регресійних snapshot-тестів.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Final

from ezdxf import new as ezdxf_new  # type: ignore[attr-defined]
from ezdxf.document import Drawing

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

# ADR-024: рівно 2 виробничі шари. Порядок важливий — впливає на байти.
DXF_LAYERS: Final[tuple[tuple[str, int], ...]] = (
    ("LASER_CUT", 7),  # white — ВСІ cut-paths (outer ByLayer + holes color 5)
    ("BEND_LINES", 3),  # green dashed — лінії гиба (не ріжуться)
)
# ACI-колір для внутрішніх вирізів (отворів): blue. Виставляється ByEntity
# на CIRCLE, щоб CAM/око відрізняли inner-cut від outer-контуру ByLayer.
_INNER_CUT_COLOR: Final[int] = 5
# Dashed linetype для BEND_LINES (setup=False не вантажить стандартні —
# додаємо власний з фіксованим pattern → детермінований).
_DASHED_LINETYPE: Final[str] = "DASHED"
_DASHED_PATTERN: Final[tuple[float, ...]] = (0.6, 0.5, -0.1)

# Фіксовані штампи часу і GUID-и для детермінованих байтів.
# Дата 2026-01-01 00:00 UTC — символічна точка відліку проєкту.
_FROZEN_JULIAN_DATE: Final[float] = 2461041.5  # 2026-01-01 00:00 UTC
_FROZEN_FINGERPRINT_GUID: Final[str] = "{00000000-0000-0000-0000-000000000001}"
_FROZEN_VERSION_GUID: Final[str] = "{00000000-0000-0000-0000-000000000002}"
_FROZEN_EZDXF_STAMP: Final[str] = "flatcraft-deterministic"

# Pattern: GUID у фігурних дужках (ezdxf $VERSIONGUID авто-генерується
# при сейві, а не на створенні — header.set() його не перекриває).
_GUID_RE: Final[re.Pattern[str]] = re.compile(
    r"\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}"
)
# Pattern: "<ezdxf-version> @ <iso-timestamp>" — DICTIONARYVAR.value у
# objects section. ezdxf пише цей рядок при write, не при create.
_EZDXF_STAMP_RE: Final[re.Pattern[str]] = re.compile(
    r"\d+\.\d+(?:\.\d+)? @ \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+[+\-]\d{2}:\d{2}"
)
# Pattern: $TDUPDATE — Julian-дата останнього save (ezdxf оновлює при write,
# минаючи header.set()). Захоплює "$TDUPDATE\n 40\n<число>".
_TDUPDATE_RE: Final[re.Pattern[str]] = re.compile(
    r"(\$TDUPDATE\n\s*40\n\s*)[\d.eE+\-]+", flags=re.MULTILINE
)


def _make_deterministic(doc: Drawing) -> None:
    """Перепризначає всі ezdxf-поля, що походять з time/uuid, на фіксовані."""
    doc.header["$TDCREATE"] = _FROZEN_JULIAN_DATE
    doc.header["$TDUPDATE"] = _FROZEN_JULIAN_DATE
    doc.header["$TDINDWG"] = 0.0  # total editing time
    doc.header["$TDUSRTIMER"] = 0.0
    doc.header["$FINGERPRINTGUID"] = _FROZEN_FINGERPRINT_GUID
    doc.header["$VERSIONGUID"] = _FROZEN_VERSION_GUID


def _export_flat_dxf(
    *,
    length_mm: float,
    width_mm: float,
    bend_lines_mm: tuple[float, ...],
    bend_radius_mm: float,
    bend_angle_deg: float,
    output_path: Path,
    holes: tuple[Hole2D, ...] = (),
    bend_directions: tuple[str, ...] = (),
) -> Path:
    """Базовий exporter: прямокутна заготовка length × width + bend lines
    на вказаних позиціях + опціональні внутрішні отвори.

    ADR-024: лише геометрія cut/bend. Текст, розміри, напрям гибу, номери —
    у PDF, не у DXF (CAM-noise). `bend_radius_mm`/`bend_angle_deg`/
    `bend_directions` лишаються у сигнатурі заради спільного API шаблонів,
    але у DXF більше не рендеряться.

    Reuse'абельний для всіх шаблонів (L/Z/corner_angle/wall_shelf).
    """
    # setup=False вимикає авто-створення VISUALSTYLE/DictionaryVariables,
    # які тримають timestamp поточної версії ezdxf і ламають детермінізм.
    doc = ezdxf_new(dxfversion="R2010", setup=False)
    _make_deterministic(doc)

    # Dashed linetype для BEND_LINES (детермінований pattern, без таблиць ezdxf-setup).
    if _DASHED_LINETYPE not in doc.linetypes:
        doc.linetypes.add(
            name=_DASHED_LINETYPE,
            pattern=list(_DASHED_PATTERN),
            description="Dashed __ __ __ (bend lines)",
        )

    for name, color in DXF_LAYERS:
        if name not in doc.layers:
            linetype = _DASHED_LINETYPE if name == "BEND_LINES" else "CONTINUOUS"
            doc.layers.add(name=name, color=color, linetype=linetype)

    msp = doc.modelspace()

    # Зовнішній контур — ByLayer (успадковує color 7 шару LASER_CUT).
    msp.add_lwpolyline(
        points=[(0, 0), (length_mm, 0), (length_mm, width_mm), (0, width_mm)],
        close=True,
        dxfattribs={"layer": "LASER_CUT"},
    )

    for bend_x in bend_lines_mm:
        msp.add_line(
            start=(bend_x, 0),
            end=(bend_x, width_mm),
            dxfattribs={"layer": "BEND_LINES"},
        )

    # Отвори — на LASER_CUT (та сама операція різання!), explicit color 5 (blue),
    # щоб inner-cut візуально відрізнявся від outer-контуру (ADR-024).
    # Phase 3.0 PR 5 (ADR-027 Рішення 6): square holes → LWPOLYLINE 4 vertices
    # замість CIRCLE. Той самий шар, та сама color 5 — DXF-інваріант 2 шари
    # збережено.
    for hole in holes:
        if hole.shape == "square":
            half = hole.diameter_mm / 2.0
            cx, cy = hole.x_mm, hole.y_mm
            msp.add_lwpolyline(
                points=[
                    (cx - half, cy - half),
                    (cx + half, cy - half),
                    (cx + half, cy + half),
                    (cx - half, cy + half),
                ],
                close=True,
                dxfattribs={"layer": "LASER_CUT", "color": _INNER_CUT_COLOR},
            )
        else:
            msp.add_circle(
                center=(hole.x_mm, hole.y_mm),
                radius=hole.diameter_mm / 2.0,
                dxfattribs={"layer": "LASER_CUT", "color": _INNER_CUT_COLOR},
            )

    doc.saveas(output_path)
    _normalize_dxf_bytes(output_path)
    return output_path


def export_l_bracket_dxf(
    unfolded: UnfoldedLBracket,
    output_path: Path,
    *,
    bend_radius_mm: float,
    bend_angle_deg: float = 90.0,
    bend_direction: str = "down",
) -> Path:
    """L-bracket DXF: один гиб у центрі."""
    return _export_flat_dxf(
        length_mm=unfolded.length_mm,
        width_mm=unfolded.width_mm,
        bend_lines_mm=(unfolded.bend_position_mm,),
        bend_radius_mm=bend_radius_mm,
        bend_angle_deg=bend_angle_deg,
        output_path=output_path,
        bend_directions=(bend_direction,),
    )


def export_z_bracket_dxf(
    unfolded: UnfoldedZBracket,
    output_path: Path,
    *,
    bend_radius_mm: float,
    bend_angle_deg: float = 90.0,
    bend_directions: tuple[str, ...] = (),
) -> Path:
    """Z-bracket DXF: два паралельні гиби."""
    return _export_flat_dxf(
        length_mm=unfolded.length_mm,
        width_mm=unfolded.width_mm,
        bend_lines_mm=unfolded.bend_positions_mm,
        bend_radius_mm=bend_radius_mm,
        bend_angle_deg=bend_angle_deg,
        output_path=output_path,
        bend_directions=bend_directions,
    )


def export_corner_angle_dxf(
    unfolded: UnfoldedCornerAngle,
    output_path: Path,
    *,
    bend_radius_mm: float,
    bend_angle_deg: float = 90.0,
    bend_direction: str = "down",
) -> Path:
    """Corner_angle DXF: один гиб + grid отворів на INNER_CUTS layer."""
    return _export_flat_dxf(
        length_mm=unfolded.length_mm,
        width_mm=unfolded.width_mm,
        bend_lines_mm=(unfolded.bend_position_mm,),
        bend_radius_mm=bend_radius_mm,
        bend_angle_deg=bend_angle_deg,
        output_path=output_path,
        holes=unfolded.holes,
        bend_directions=(bend_direction,),
    )


def export_wall_shelf_dxf(
    unfolded: UnfoldedWallShelf,
    output_path: Path,
    *,
    bend_radius_mm: float,
    bend_angle_deg: float = 90.0,
    bend_directions: tuple[str, ...] = (),
) -> Path:
    """Wall_shelf DXF: 1 або 2 bends + mount holes на back-секції."""
    return _export_flat_dxf(
        length_mm=unfolded.length_mm,
        width_mm=unfolded.width_mm,
        bend_lines_mm=unfolded.bend_positions_mm,
        bend_radius_mm=bend_radius_mm,
        bend_angle_deg=bend_angle_deg,
        output_path=output_path,
        holes=unfolded.holes,
        bend_directions=bend_directions,
    )


def export_perforated_panel_dxf(
    unfolded: UnfoldedPerforatedPanel,
    output_path: Path,
) -> Path:
    """Perforated_panel DXF: лише прямокутник + grid отворів, без bends."""
    # bend_radius_mm/bend_angle_deg формально потрібні API, але цикл по
    # bend_lines_mm=() не виконається — їхні значення не використовуються.
    return _export_flat_dxf(
        length_mm=unfolded.length_mm,
        width_mm=unfolded.width_mm,
        bend_lines_mm=(),
        bend_radius_mm=0.0,
        bend_angle_deg=0.0,
        output_path=output_path,
        holes=unfolded.holes,
    )


def export_perforated_panel_square_dxf(
    unfolded: UnfoldedPerforatedPanelSquare,
    output_path: Path,
) -> Path:
    """Перфо-монтажна панель DXF — cross-розгортка лотка (ADR-030).

    Cross-outline (1 LWPOLYLINE на LASER_CUT, ByLayer; bulge≠0 на скруглених
    R-кутах ребер) + 4 BEND_LINES (dashed) + перфорація (square LWPOLYLINE,
    color 5) + 4 установочні отвори Ø5.5 (CIRCLE, color 5).

    Інваріант ADR-024 збережено: рівно 2 виробничі шари, 0 TEXT/DIMENSION
    (кріпильні розміри/напрям — у PDF).
    """
    doc = ezdxf_new(dxfversion="R2010", setup=False)
    _make_deterministic(doc)

    if _DASHED_LINETYPE not in doc.linetypes:
        doc.linetypes.add(
            name=_DASHED_LINETYPE,
            pattern=list(_DASHED_PATTERN),
            description="Dashed __ __ __ (bend lines)",
        )
    for name, color in DXF_LAYERS:
        if name not in doc.layers:
            linetype = _DASHED_LINETYPE if name == "BEND_LINES" else "CONTINUOUS"
            doc.layers.add(name=name, color=color, linetype=linetype)

    msp = doc.modelspace()

    # Cross-outline на LASER_CUT (ByLayer color 7); bulge несе R-скруглення ребер.
    msp.add_lwpolyline(
        points=list(unfolded.outline_lw),
        format="xyb",
        close=True,
        dxfattribs={"layer": "LASER_CUT"},
    )

    # Лінії гибу (4 axis-aligned segments) на BEND_LINES (dashed green).
    for bend in unfolded.bend_lines:
        msp.add_line(
            start=(bend.x1_mm, bend.y1_mm),
            end=(bend.x2_mm, bend.y2_mm),
            dxfattribs={"layer": "BEND_LINES"},
        )

    # Перфорація — square LWPOLYLINE (color 5) на тому ж LASER_CUT (ADR-024).
    for hole in unfolded.holes:
        half = hole.diameter_mm / 2.0
        msp.add_lwpolyline(
            points=[
                (hole.x_mm - half, hole.y_mm - half),
                (hole.x_mm + half, hole.y_mm - half),
                (hole.x_mm + half, hole.y_mm + half),
                (hole.x_mm - half, hole.y_mm + half),
            ],
            close=True,
            dxfattribs={"layer": "LASER_CUT", "color": _INNER_CUT_COLOR},
        )

    # Установочні отвори Ø5.5 — CIRCLE (color 5), inner-cut на LASER_CUT.
    for hole in unfolded.corner_holes:
        msp.add_circle(
            center=(hole.x_mm, hole.y_mm),
            radius=hole.diameter_mm / 2.0,
            dxfattribs={"layer": "LASER_CUT", "color": _INNER_CUT_COLOR},
        )

    doc.saveas(output_path)
    _normalize_dxf_bytes(output_path)
    return output_path


def export_enclosed_shelf_dxf(
    unfolded: UnfoldedEnclosedShelf,
    output_path: Path,
) -> Path:
    """Enclosed_shelf DXF (Phase 3.0 PR 7b, ADR-027 Рішення 5).

    Cross-розгортка: один LWPOLYLINE на LASER_CUT (cross-shape outline,
    ByLayer color 7) + 3-4 BEND_LINES (axis-aligned segments, dashed) +
    опціональні side perforation holes (квадратні LWPOLYLINEs, color 5).

    Інваріант ADR-024 збережено: 2 виробничі шари, 0 TEXT/DIMENSION.
    """
    doc = ezdxf_new(dxfversion="R2010", setup=False)
    _make_deterministic(doc)

    if _DASHED_LINETYPE not in doc.linetypes:
        doc.linetypes.add(
            name=_DASHED_LINETYPE,
            pattern=list(_DASHED_PATTERN),
            description="Dashed __ __ __ (bend lines)",
        )
    for name, color in DXF_LAYERS:
        if name not in doc.layers:
            linetype = _DASHED_LINETYPE if name == "BEND_LINES" else "CONTINUOUS"
            doc.layers.add(name=name, color=color, linetype=linetype)

    msp = doc.modelspace()

    # Cross-outline на LASER_CUT (ByLayer color 7).
    msp.add_lwpolyline(
        points=list(unfolded.outline_vertices),
        close=True,
        dxfattribs={"layer": "LASER_CUT"},
    )

    # Bend lines (3-4 axis-aligned segments) на BEND_LINES (dashed green).
    for bend in unfolded.bend_lines:
        msp.add_line(
            start=(bend.x1_mm, bend.y1_mm),
            end=(bend.x2_mm, bend.y2_mm),
            dxfattribs={"layer": "BEND_LINES"},
        )

    # Опціональні side perforation holes — квадратні (LWPOLYLINE color 5)
    # на тому ж LASER_CUT layer (ADR-024 інваріант: lonе 2 шари).
    for hole in unfolded.side_holes:
        if hole.shape == "square":
            half = hole.diameter_mm / 2.0
            msp.add_lwpolyline(
                points=[
                    (hole.x_mm - half, hole.y_mm - half),
                    (hole.x_mm + half, hole.y_mm - half),
                    (hole.x_mm + half, hole.y_mm + half),
                    (hole.x_mm - half, hole.y_mm + half),
                ],
                close=True,
                dxfattribs={"layer": "LASER_CUT", "color": _INNER_CUT_COLOR},
            )
        else:
            msp.add_circle(
                center=(hole.x_mm, hole.y_mm),
                radius=hole.diameter_mm / 2.0,
                dxfattribs={"layer": "LASER_CUT", "color": _INNER_CUT_COLOR},
            )

    doc.saveas(output_path)
    _normalize_dxf_bytes(output_path)
    return output_path


def _normalize_dxf_bytes(path: Path) -> None:
    """Заміщає недетерміновані GUID/timestamp у збереженому файлі.

    ezdxf пише ці поля під час `saveas`, минаючи header.set() — тому
    очищаємо їх пост-фактум. Без цього однаковий вхід дає різні байти,
    що ламає snapshot-тести (CLAUDE.md §2.4).
    """
    text = path.read_text(encoding="utf-8")
    # Лишаємо два керовані header-GUID-и (frozen константи) і замінюємо решту.
    placeholder_guid = "{00000000-0000-0000-0000-000000000003}"

    def _replace_guid(match: re.Match[str]) -> str:
        value = match.group(0)
        if value in (_FROZEN_FINGERPRINT_GUID, _FROZEN_VERSION_GUID):
            return value
        return placeholder_guid

    text = _GUID_RE.sub(_replace_guid, text)
    text = _EZDXF_STAMP_RE.sub(_FROZEN_EZDXF_STAMP, text)
    text = _TDUPDATE_RE.sub(rf"\g<1>{_FROZEN_JULIAN_DATE}", text)
    path.write_text(text, encoding="utf-8")
