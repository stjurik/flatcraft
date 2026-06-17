"""Тести Python profile-валідатора (Hotfix 2.9.f, ADR-026).

Паритет із TS `validateProfile` + assertion'ами geometry.ts. Включає
property-based parity (hypothesis, 300 прикладів) проти незалежного oracle —
дзеркало `packages/cad-engine/src/validators/profile.property.test.ts`.
"""

from __future__ import annotations

from hypothesis import given, settings
from hypothesis import strategies as st

from flatcraft_cad.validate.profile import validate_profile


def _codes(template_slug: str, params: dict[str, float], t: float) -> list[str]:
    return [e.code for e in validate_profile(template_slug, params, t)]


def _fields(template_slug: str, params: dict[str, float], t: float) -> set[str]:
    return {e.field for e in validate_profile(template_slug, params, t)}


class TestProfileUnit:
    def test_corner_angle_leg_a_too_short(self) -> None:
        errs = validate_profile(
            "corner_angle",
            {"legA_mm": 1, "legB_mm": 60, "bend_radius_mm": 2.5},
            2,
        )
        assert len(errs) == 1
        assert errs[0].code == "LEG_TOO_SHORT"
        assert errs[0].field == "legA"
        assert "4.5" in errs[0].detail

    def test_corner_angle_leg_on_boundary_ok(self) -> None:
        # legA = t+r = 4.5 не кидає (inclusive).
        assert (
            validate_profile(
                "corner_angle", {"legA_mm": 4.5, "legB_mm": 60, "bend_radius_mm": 2.5}, 2
            )
            == []
        )

    def test_z_bracket_offset_and_flange(self) -> None:
        assert _fields(
            "z_bracket",
            {"top_flange_mm": 4.5, "bottom_flange_mm": 60, "offset_mm": 2.5, "bend_radius_mm": 2.5},
            2,
        ) == {"top_flange", "offset"}

    def test_wall_shelf_shelf_double_bend(self) -> None:
        # lip>0 → потрібно sd > 2(t+r)=9; sd=9 → SHELF_TOO_SHORT.
        assert _codes(
            "wall_shelf",
            {
                "back_height_mm": 80,
                "shelf_depth_mm": 9,
                "front_lip_mm": 20,
                "bend_radius_mm": 2.5,
            },
            2,
        ) == ["SHELF_TOO_SHORT"]

    def test_perforated_panel_immune(self) -> None:
        assert validate_profile("perforated_panel", {"length_mm": 1, "width_mm": 1}, 2) == []

    def test_thickness_zero_no_error(self) -> None:
        assert (
            validate_profile("corner_angle", {"legA_mm": 1, "legB_mm": 1, "bend_radius_mm": 2.5}, 0)
            == []
        )


_T = [0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0]
_R = [0.5, 1.0, 2.5, 4.0, 5.0]
_DIM = [0.5, 1.0, 2.0, 4.0, 4.5, 5.0, 9.0, 10.0, 50.0, 100.0, 500.0]


@settings(max_examples=300)
@given(
    t=st.sampled_from(_T),
    r=st.sampled_from(_R),
    leg_a=st.sampled_from(_DIM),
    leg_b=st.sampled_from(_DIM),
)
def test_legs_property_parity(t: float, r: float, leg_a: float, leg_b: float) -> None:
    """Oracle: issue для leg ⇔ leg < t+r (дзеркало TS property)."""
    fields = _fields("corner_angle", {"legA_mm": leg_a, "legB_mm": leg_b, "bend_radius_mm": r}, t)
    assert ("legA" in fields) == (leg_a < t + r)
    assert ("legB" in fields) == (leg_b < t + r)


@settings(max_examples=300)
@given(
    t=st.sampled_from(_T),
    r=st.sampled_from(_R),
    bh=st.sampled_from(_DIM),
    sd=st.sampled_from(_DIM),
    lip=st.sampled_from([0.0, 20.0]),
)
def test_wall_shelf_property_parity(t: float, r: float, bh: float, sd: float, lip: float) -> None:
    fields = _fields(
        "wall_shelf",
        {"back_height_mm": bh, "shelf_depth_mm": sd, "front_lip_mm": lip, "bend_radius_mm": r},
        t,
    )
    threshold = 2 * (t + r) if lip > 0 else (t + r)
    assert ("back_height" in fields) == (bh <= t + r)
    assert ("shelf_depth" in fields) == (sd <= threshold)
