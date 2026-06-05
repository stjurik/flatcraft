"""Авто-вибір кута аркуша для блоку анотацій (Phase 2.9.b Block E).

Розмірні блоки (BOM, таблиця гибів) треба ставити у кут аркуша з найбільшим
вільним простором, щоб не перекривати геометрію розгортки. Ця pure-функція
рахує, який з 4 кутів вміщає блок анотації з найбільшим запасом.

Модель вільного простору: для кожного кута беремо прямокутник, затиснутий
між цим кутом аркуша і роздутою на margin_mm геометрією — по обох осях. Це
«вільний прямокутник у куті». Вибираємо кут, де він вміщає блок анотації з
найбільшим мінімальним запасом.

Чиста геометрія у мм → юніт-тести без ReportLab.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class Corner(Enum):
    """Кут аркуша для розміщення блоку анотації."""

    TL = "top-left"
    TR = "top-right"
    BL = "bottom-left"
    BR = "bottom-right"


@dataclass(frozen=True)
class BBox2D:
    """Прямокутник у мм (page-space): нижній-лівий + верхній-правий."""

    x_min: float
    y_min: float
    x_max: float
    y_max: float

    @property
    def width(self) -> float:
        return self.x_max - self.x_min

    @property
    def height(self) -> float:
        return self.y_max - self.y_min


@dataclass(frozen=True)
class Size2D:
    """Габарит блоку анотації у мм."""

    width_mm: float
    height_mm: float


# Порядок перебору кутів — фіксований; визначає tie-break (перший max виграє).
_CORNER_ORDER: tuple[Corner, ...] = (Corner.TL, Corner.TR, Corner.BL, Corner.BR)


def _free_rect(
    corner: Corner,
    geometry: BBox2D,
    page: BBox2D,
    margin_mm: float,
) -> tuple[float, float]:
    """Вільний прямокутник (width, height) у куті — затиснутий між кутом
    аркуша і роздутою геометрією по обох осях."""
    gx0 = geometry.x_min - margin_mm
    gy0 = geometry.y_min - margin_mm
    gx1 = geometry.x_max + margin_mm
    gy1 = geometry.y_max + margin_mm

    # free_w — ліворуч/праворуч від геометрії; free_h — під/над нею.
    free_w = gx0 - page.x_min if corner in (Corner.TL, Corner.BL) else page.x_max - gx1
    free_h = gy0 - page.y_min if corner in (Corner.BL, Corner.BR) else page.y_max - gy1
    return max(free_w, 0.0), max(free_h, 0.0)


def pick_annotation_corner(
    geometry_bbox: BBox2D,
    page_bbox: BBox2D,
    annotation_size: Size2D,
    margin_mm: float = 10.0,
) -> Corner:
    """Кут аркуша з найбільшим запасом під блок анотації розміром annotation_size.

    Повертає кут, де блок вміщається (у вертикальній АБО горизонтальній смузі)
    з найбільшим мінімальним запасом. Якщо жоден кут не вміщає — fallback BR
    (поточний дефолт; реально означає overflow до другого аркуша — окремий Phase).

    Кидає ValueError, якщо сам аркуш менший за блок анотації.
    """
    if annotation_size.width_mm > page_bbox.width or annotation_size.height_mm > page_bbox.height:
        raise ValueError(
            f"анотація {annotation_size.width_mm}×{annotation_size.height_mm} мм не влазить "
            f"в аркуш {page_bbox.width}×{page_bbox.height} мм"
        )

    best_corner: Corner | None = None
    best_slack = float("-inf")
    for corner in _CORNER_ORDER:
        fw, fh = _free_rect(corner, geometry_bbox, page_bbox, margin_mm)
        if fw >= annotation_size.width_mm and fh >= annotation_size.height_mm:
            slack = min(fw - annotation_size.width_mm, fh - annotation_size.height_mm)
            if slack > best_slack:
                best_slack = slack
                best_corner = corner

    return best_corner if best_corner is not None else Corner.BR
