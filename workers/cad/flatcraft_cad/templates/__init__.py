"""Параметричні шаблони листового металу."""

from flatcraft_cad.templates.base import Template
from flatcraft_cad.templates.corner_angle import (
    CornerAngleBuildParameters,
    CornerAngleTemplate,
    build_corner_angle,
)
from flatcraft_cad.templates.l_bracket import (
    LBracketBuildParameters,
    LBracketTemplate,
    build_l_bracket,
)
from flatcraft_cad.templates.perforated_panel import (
    PerforatedPanelBuildParameters,
    PerforatedPanelTemplate,
    build_perforated_panel,
)
from flatcraft_cad.templates.wall_shelf import (
    WallShelfBuildParameters,
    WallShelfTemplate,
    build_wall_shelf,
)
from flatcraft_cad.templates.z_bracket import (
    ZBracketBuildParameters,
    ZBracketTemplate,
    build_z_bracket,
)

__all__ = [
    "CornerAngleBuildParameters",
    "CornerAngleTemplate",
    "LBracketBuildParameters",
    "LBracketTemplate",
    "PerforatedPanelBuildParameters",
    "PerforatedPanelTemplate",
    "Template",
    "WallShelfBuildParameters",
    "WallShelfTemplate",
    "ZBracketBuildParameters",
    "ZBracketTemplate",
    "build_corner_angle",
    "build_l_bracket",
    "build_perforated_panel",
    "build_wall_shelf",
    "build_z_bracket",
]
