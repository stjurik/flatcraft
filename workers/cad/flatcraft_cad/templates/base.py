"""Абстрактний клас шаблону.

Кожен виріб (l_bracket, z_bracket, ...) реалізує `Template` як легкий
адаптер між Pydantic-параметрами і CadQuery-моделлю. Бізнес-логіка
(розгортка, експорт, валідація) працює з `cq.Workplane`, який повертає
`build()` — single source of geometry.
"""

from abc import ABC, abstractmethod
from typing import Literal

import cadquery as cq
from pydantic import BaseModel, ConfigDict, Field

BendDirection = Literal["up", "down"]


class BendSpec(BaseModel):
    """Напрям одного гибу (Hotfix 2.10.e). Дзеркало TS `BendSpecSchema`.

    Дефолт 'down' за рішенням замовника. Напрям не впливає на геометрію
    розгортки (довжину/позиції гибів) — лише на рендер стрілки у DXF/PDF.
    """

    model_config = ConfigDict(frozen=True)

    direction: BendDirection = Field(default="down", description="Напрям згину: up/down.")


class Template[ParamsT: BaseModel](ABC):
    """Контракт шаблону: name (slug) + build(params) → cq.Workplane."""

    name: str

    @abstractmethod
    def build(self, params: ParamsT) -> cq.Workplane:
        """Збирає 3D-модель за параметрами. Pure-функція: однакові
        params → байт-у-байт однакова геометрія (CLAUDE.md §2.4)."""
