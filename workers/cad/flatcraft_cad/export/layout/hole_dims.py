"""Логіка розмірних виносок отворів (Phase 2.9.b Block F).

Чиста політика: чи дімити кожен отвір окремо, чи (для перфо-панелі з
сотнями отворів) показати один розмір + текстову анотацію «×N отворів».
Виносити dim на кожен з сотень отворів — нечитабельно і роздуває DXF.
"""

from __future__ import annotations

from typing import Final

# Максимум отворів, які дімимо індивідуально. Більше — один dim + «×N».
HOLE_DIM_CAP: Final[int] = 10


def should_dim_individual_holes(count: int, cap: int = HOLE_DIM_CAP) -> bool:
    """True, якщо отворів небагато (≤ cap) і кожен можна підписати окремо."""
    return count <= cap
