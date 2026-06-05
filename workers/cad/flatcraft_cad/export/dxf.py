"""DXF-експорт розгорнутих листометалевих виробів.

Шари відповідають конвенції виробництва лазерного різання + гибки:
- LASER_CUT: зовнішній контур, який різатиме лазер.
- INNER_CUTS: внутрішні вирізи (отвори, прорізи) — на тій же операції різання.
- BEND_LINES: лінії, по яких гнутий метал (info для оператора, не ріжуться).
- BEND_TEXT: текст біля BEND_LINES ("BEND 90° UP R2.5" тощо).
- DIM: розміри для довідки.

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
    UnfoldedLBracket,
    UnfoldedPerforatedPanel,
    UnfoldedWallShelf,
    UnfoldedZBracket,
)

# Шари, які створюємо у кожному DXF (порядок важливий — впливає на байти).
DXF_LAYERS: Final[tuple[tuple[str, int], ...]] = (
    ("LASER_CUT", 7),  # white/black — основний контур
    ("INNER_CUTS", 1),  # red — внутрішні вирізи
    ("BEND_LINES", 5),  # blue — лінії гиба
    ("BEND_TEXT", 3),  # green — анотації
    ("DIM", 8),  # сірий — розміри
)

# Фіксовані штампи часу і GUID-и для детермінованих байтів.
# Дата 2026-01-01 00:00 UTC — символічна точка відліку проєкту.
_FROZEN_JULIAN_DATE: Final[float] = 2461041.5  # 2026-01-01 00:00 UTC
_FROZEN_FINGERPRINT_GUID: Final[str] = "{00000000-0000-0000-0000-000000000001}"
_FROZEN_VERSION_GUID: Final[str] = "{00000000-0000-0000-0000-000000000002}"
_FROZEN_EZDXF_STAMP: Final[str] = "flatcraft-deterministic"
_BEND_TEXT_HEIGHT_MM: Final[float] = 3.0
# Phase 2.9.b Block B: окремий короткий "#N" badge ПОСЕРЕДИНІ лінії гибу
# (на додачу до повного callout зверху). Трохи більший за callout, щоб
# впадав у вічі оператору, який дивиться лише на лінію.
_BEND_BADGE_TEXT_HEIGHT_MM: Final[float] = 3.5

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


def _bend_label(direction: str) -> str:
    """ASCII-мітка напряму для DXF (↓/↑ Unicode не гарантовано у всіх в'юверах)."""
    return "UP" if direction == "up" else "DOWN"


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

    Reuse'абельний для всіх шаблонів (L/Z/corner_angle/wall_shelf).
    """
    # setup=False вимикає авто-створення VISUALSTYLE/DictionaryVariables,
    # які тримають timestamp поточної версії ezdxf і ламають детермінізм.
    doc = ezdxf_new(dxfversion="R2010", setup=False)
    _make_deterministic(doc)

    for name, color in DXF_LAYERS:
        if name not in doc.layers:
            doc.layers.add(name=name, color=color)

    msp = doc.modelspace()

    msp.add_lwpolyline(
        points=[(0, 0), (length_mm, 0), (length_mm, width_mm), (0, width_mm)],
        close=True,
        dxfattribs={"layer": "LASER_CUT"},
    )

    for n, bend_x in enumerate(bend_lines_mm):
        direction = bend_directions[n] if n < len(bend_directions) else "down"
        msp.add_line(
            start=(bend_x, 0),
            end=(bend_x, width_mm),
            dxfattribs={"layer": "BEND_LINES"},
        )
        # Префікс "BEND {angle}°" збережено навмисно (Hotfix 2.10.e): додаємо
        # напрям (DOWN/UP) і номер гибу #{n}, не ламаючи існуючих перевірок.
        msp.add_text(
            f"BEND {bend_angle_deg:g}° {_bend_label(direction)} R{bend_radius_mm:g} #{n + 1}",
            dxfattribs={
                "layer": "BEND_TEXT",
                "height": _BEND_TEXT_HEIGHT_MM,
                "insert": (bend_x + 1.0, width_mm + 1.0),
            },
        )
        # Midpoint badge: самий "#N" на середині лінії — друга підказка для
        # оператора (Phase 2.9.b Block B). Той самий BEND_TEXT шар; ASCII "#N".
        msp.add_text(
            f"#{n + 1}",
            dxfattribs={
                "layer": "BEND_TEXT",
                "height": _BEND_BADGE_TEXT_HEIGHT_MM,
                "insert": (bend_x + 1.0, width_mm / 2.0),
            },
        )

    for hole in holes:
        msp.add_circle(
            center=(hole.x_mm, hole.y_mm),
            radius=hole.diameter_mm / 2.0,
            dxfattribs={"layer": "INNER_CUTS"},
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
