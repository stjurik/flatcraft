"""Pydantic parse tests для EnclosedShelfBuildParameters (Phase 3.0 PR 7a).

Builder/unfold/export — у PR 7b/7c.
"""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from flatcraft_cad.templates.base import BendSpec
from flatcraft_cad.templates.enclosed_shelf import (
    EnclosedShelfBuildParameters,
    EnclosedShelfSidePerforation,
    EnclosedShelfStiffeningRib,
)


def _valid_params(**overrides: object) -> dict[str, object]:
    base: dict[str, object] = {
        "width_mm": 600,
        "depth_mm": 200,
        "bend_radius_mm": 2.5,
        "thickness_mm": 1.5,
    }
    base.update(overrides)
    return base


def test_accepts_minimal_valid_params() -> None:
    p = EnclosedShelfBuildParameters.model_validate(_valid_params())
    assert p.width_mm == 600
    assert p.depth_mm == 200
    assert p.bend_angle_deg == 90
    # Default: 4 bends, all 'up'.
    assert len(p.bends) == 4
    assert all(b.direction == "up" for b in p.bends)
    # Optional features default to None.
    assert p.side_perforation is None
    assert p.stiffening_rib is None


def test_accepts_min_max_dimensions() -> None:
    EnclosedShelfBuildParameters.model_validate(_valid_params(width_mm=300, depth_mm=100))
    EnclosedShelfBuildParameters.model_validate(_valid_params(width_mm=1000, depth_mm=300))


def test_rejects_width_below_min() -> None:
    with pytest.raises(ValidationError):
        EnclosedShelfBuildParameters.model_validate(_valid_params(width_mm=250))


def test_rejects_depth_above_max() -> None:
    with pytest.raises(ValidationError):
        EnclosedShelfBuildParameters.model_validate(_valid_params(depth_mm=350))


def test_rejects_disallowed_bend_radius() -> None:
    with pytest.raises(ValidationError):
        EnclosedShelfBuildParameters.model_validate(_valid_params(bend_radius_mm=3.0))


def test_accepts_3_bends_no_rib() -> None:
    p = EnclosedShelfBuildParameters.model_validate(
        _valid_params(bends=(BendSpec(direction="up"),) * 3)
    )
    assert len(p.bends) == 3


def test_rejects_2_bends() -> None:
    with pytest.raises(ValidationError):
        EnclosedShelfBuildParameters.model_validate(
            _valid_params(bends=(BendSpec(direction="up"),) * 2)
        )


def test_rejects_5_bends() -> None:
    with pytest.raises(ValidationError):
        EnclosedShelfBuildParameters.model_validate(
            _valid_params(bends=(BendSpec(direction="up"),) * 5)
        )


def test_accepts_optional_side_perforation() -> None:
    p = EnclosedShelfBuildParameters.model_validate(
        _valid_params(
            side_perforation=EnclosedShelfSidePerforation(
                hole_size_mm=8, pitch_x_mm=30, pitch_y_mm=30, margin_mm=15
            )
        )
    )
    assert p.side_perforation is not None
    assert p.side_perforation.hole_size_mm == 8


def test_accepts_optional_stiffening_rib() -> None:
    p = EnclosedShelfBuildParameters.model_validate(
        _valid_params(stiffening_rib=EnclosedShelfStiffeningRib(height_mm=15))
    )
    assert p.stiffening_rib is not None
    assert p.stiffening_rib.height_mm == 15


def test_side_perforation_rejects_oversized_hole() -> None:
    with pytest.raises(ValidationError):
        EnclosedShelfSidePerforation(hole_size_mm=25, pitch_x_mm=30, pitch_y_mm=30, margin_mm=15)


def test_stiffening_rib_rejects_height_below_min() -> None:
    with pytest.raises(ValidationError):
        EnclosedShelfStiffeningRib(height_mm=3)


def test_frozen_model_disallows_mutation() -> None:
    p = EnclosedShelfBuildParameters.model_validate(_valid_params())
    with pytest.raises(ValidationError):
        # Pydantic frozen=True raises ValidationError on field assignment.
        p.width_mm = 700
