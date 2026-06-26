"""Тести Python perforation-валідатора (паритет з TS validatePerforation).

Правило: pitch > hole_size → валідно; pitch <= hole_size → HOLES_OVERLAP.
Уніфікований шаблон `perforated_panel` (ADR-031): hole_size = `hole_size_mm`,
слово у повідомленні («сторону»/«діаметр») — за `hole_shape`. Включає
property-based parity проти незалежного oracle — дзеркало
`packages/cad-engine/src/validators/perforation.test.ts`.
"""

from __future__ import annotations

from hypothesis import given, settings
from hypothesis import strategies as st

from flatcraft_cad.validate.perforation import validate_perforation


class TestPerforationUnit:
    def test_square_clean_grid_valid(self) -> None:
        errs = validate_perforation(
            "perforated_panel",
            {"hole_shape": "square", "hole_size_mm": 8, "pitch_x_mm": 30, "pitch_y_mm": 30},
        )
        assert errs == []

    def test_square_pitch_y_below_side_overlaps(self) -> None:
        errs = validate_perforation(
            "perforated_panel",
            {"hole_shape": "square", "hole_size_mm": 20, "pitch_x_mm": 27, "pitch_y_mm": 10},
        )
        assert len(errs) == 1
        assert errs[0].code == "HOLES_OVERLAP"
        assert errs[0].field == "pitch_y_mm"
        assert "сторону" in errs[0].detail

    def test_square_touching_zero_ligament_invalid(self) -> None:
        # pitch == hole_size → торкання, нульовий місток → обидві осі invalid.
        errs = validate_perforation(
            "perforated_panel",
            {"hole_shape": "square", "hole_size_mm": 30, "pitch_x_mm": 30, "pitch_y_mm": 30},
        )
        assert {e.field for e in errs} == {"pitch_x_mm", "pitch_y_mm"}

    def test_round_below_diameter_overlaps(self) -> None:
        errs = validate_perforation(
            "perforated_panel",
            {"hole_shape": "circle", "hole_size_mm": 25, "pitch_x_mm": 12, "pitch_y_mm": 12},
        )
        assert len(errs) == 2
        assert "діаметр" in errs[0].detail

    def test_unknown_slug_returns_empty(self) -> None:
        assert validate_perforation("l_bracket", {"pitch_x_mm": 5}) == []

    def test_missing_hole_size_returns_empty(self) -> None:
        assert validate_perforation("perforated_panel", {"pitch_x_mm": 5, "pitch_y_mm": 5}) == []


def _oracle_overlaps(hole_size: float, pitch_x: float, pitch_y: float) -> set[str]:
    """Незалежний референс: вісь invalid коли pitch <= hole_size."""
    fields: set[str] = set()
    if pitch_x <= hole_size:
        fields.add("pitch_x_mm")
    if pitch_y <= hole_size:
        fields.add("pitch_y_mm")
    return fields


@settings(max_examples=300)
@given(
    hole=st.floats(min_value=3, max_value=30),
    px=st.floats(min_value=10, max_value=200),
    py=st.floats(min_value=10, max_value=200),
    square=st.booleans(),
)
def test_property_parity_with_oracle(hole: float, px: float, py: float, square: bool) -> None:
    shape = "square" if square else "circle"
    errs = validate_perforation(
        "perforated_panel",
        {"hole_shape": shape, "hole_size_mm": hole, "pitch_x_mm": px, "pitch_y_mm": py},
    )
    assert {e.field for e in errs} == _oracle_overlaps(hole, px, py)
    assert all(e.code == "HOLES_OVERLAP" for e in errs)
