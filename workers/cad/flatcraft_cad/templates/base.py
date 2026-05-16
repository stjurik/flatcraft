"""Абстрактний клас шаблону.

Кожен виріб (l_bracket, z_bracket, ...) реалізує `Template` як легкий
адаптер між Pydantic-параметрами і CadQuery-моделлю. Бізнес-логіка
(розгортка, експорт, валідація) працює з `cq.Workplane`, який повертає
`build()` — single source of geometry.
"""

from abc import ABC, abstractmethod

import cadquery as cq
from pydantic import BaseModel


class Template[ParamsT: BaseModel](ABC):
    """Контракт шаблону: name (slug) + build(params) → cq.Workplane."""

    name: str

    @abstractmethod
    def build(self, params: ParamsT) -> cq.Workplane:
        """Збирає 3D-модель за параметрами. Pure-функція: однакові
        params → байт-у-байт однакова геометрія (CLAUDE.md §2.4)."""
