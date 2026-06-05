"""Розміщення badge'ів з номерами гибів на лініях розгортки (Phase 2.9.b Block B).

Badge — маленьке коло Ø5мм з номером гибу, що ставиться ПОСЕРЕДИНІ лінії
гибу. Це друга візуальна підказка на додачу до повного callout збоку
(`BEND #1 DOWN R2.5 d=...`), для оператора, який дивиться лише на лінію.

Два крайових випадки:
1. Лінія коротша за поріг — badge зміщується вище краю з виноскою-рискою.
2. Дві лінії надто близько по X — другий badge зсувається по Y (з виноскою),
   щоб кола не перекривались.

Координати у model-space мм (та сама система, що довжина×ширина заготовки).
Чиста геометрія → юніт-тести без ReportLab/ezdxf.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Final

# Діаметр кола badge у мм (узгоджено з PDF-рендером _draw_unfold*).
BADGE_DIAMETER_MM: Final[float] = 5.0
# Якщо лінія коротша за це — badge не вміщається інлайн і йде на виноску.
MIN_LINE_LEN_FOR_INLINE_MM: Final[float] = 8.0
# На скільки зсувати badge при overlap / короткій лінії (по Y, від лінії).
_BADGE_OFFSET_MM: Final[float] = BADGE_DIAMETER_MM * 1.4


@dataclass(frozen=True)
class BendLine2D:
    """Вертикальна лінія гибу у model-space: x фіксований, y від start до end."""

    number: int  # 1-based номер гибу (як у callout #N)
    x_mm: float
    y_start_mm: float
    y_end_mm: float

    @property
    def midpoint_mm(self) -> tuple[float, float]:
        return (self.x_mm, (self.y_start_mm + self.y_end_mm) / 2.0)

    @property
    def length_mm(self) -> float:
        return abs(self.y_end_mm - self.y_start_mm)


@dataclass(frozen=True)
class BendBadge:
    """Готова позиція badge'а для рендерингу.

    `(x_mm, y_mm)` — центр кола. Якщо `has_leader`, рендер має домалювати
    тонку риску від кола до `(leader_to_x_mm, leader_to_y_mm)` (точка на лінії).
    """

    number: int
    x_mm: float
    y_mm: float
    has_leader: bool
    leader_to_x_mm: float
    leader_to_y_mm: float


def place_bend_badges(bend_lines: tuple[BendLine2D, ...]) -> tuple[BendBadge, ...]:
    """Обчислює позиції badge'ів для всіх ліній гибу.

    Порядок вихідних badge'ів збігається з порядком вхідних ліній (номери
    зберігаються як є — не перенумеровуються). Детерміновано: однаковий
    вхід → однаковий вихід.
    """
    placed: list[BendBadge] = []
    for line in bend_lines:
        mid_x, mid_y = line.midpoint_mm

        if line.length_mm < MIN_LINE_LEN_FOR_INLINE_MM:
            # Коротка лінія — badge над верхнім краєм, виноска до midpoint.
            top = max(line.y_start_mm, line.y_end_mm)
            placed.append(
                BendBadge(
                    number=line.number,
                    x_mm=mid_x,
                    y_mm=top + _BADGE_OFFSET_MM,
                    has_leader=True,
                    leader_to_x_mm=mid_x,
                    leader_to_y_mm=mid_y,
                )
            )
            continue

        # Кандидат — інлайн на midpoint. Перевіряємо overlap з уже розміщеними.
        cand_y = mid_y
        overlaps = _overlaps_existing(placed, mid_x, cand_y)
        if overlaps:
            # Зсуваємо вгору, доки не перестане накладатись (детерміновано).
            shifted_y = mid_y
            while _overlaps_existing(placed, mid_x, shifted_y):
                shifted_y += _BADGE_OFFSET_MM
            placed.append(
                BendBadge(
                    number=line.number,
                    x_mm=mid_x,
                    y_mm=shifted_y,
                    has_leader=True,
                    leader_to_x_mm=mid_x,
                    leader_to_y_mm=mid_y,
                )
            )
        else:
            placed.append(
                BendBadge(
                    number=line.number,
                    x_mm=mid_x,
                    y_mm=cand_y,
                    has_leader=False,
                    leader_to_x_mm=mid_x,
                    leader_to_y_mm=mid_y,
                )
            )

    return tuple(placed)


def _overlaps_existing(placed: list[BendBadge], x_mm: float, y_mm: float) -> bool:
    """Чи накладається коло (x,y) на якесь уже розміщене (центри ближче за діаметр)."""
    for b in placed:
        if abs(b.x_mm - x_mm) < BADGE_DIAMETER_MM and abs(b.y_mm - y_mm) < BADGE_DIAMETER_MM:
            return True
    return False
