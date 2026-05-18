"""Параметричні шаблони листового металу.

Кожен шаблон — окремий модуль (l_bracket, z_bracket, ...) з власною
Pydantic-схемою параметрів і build-функцією, що повертає cq.Workplane.
"""

from flatcraft_cad.templates.base import Template
from flatcraft_cad.templates.l_bracket import (
    LBracketBuildParameters,
    LBracketTemplate,
    build_l_bracket,
)
from flatcraft_cad.templates.z_bracket import (
    ZBracketBuildParameters,
    ZBracketTemplate,
    build_z_bracket,
)

__all__ = [
    "LBracketBuildParameters",
    "LBracketTemplate",
    "Template",
    "ZBracketBuildParameters",
    "ZBracketTemplate",
    "build_l_bracket",
    "build_z_bracket",
]
