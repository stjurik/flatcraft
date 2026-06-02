"""Property-based parity тести Python-валідатора гиба (Hotfix 2.10.e C).

Дзеркало `packages/cad-engine/src/validators/bend.property.test.ts`: той самий
oracle, той самий YAML. Для будь-якої (матеріал, товщина, радіус):
  - матриця дозволяє → validate_bend повертає [];
  - матриця забороняє / невідома комбінація → ≥1 помилка.
1000 прикладів.
"""

from __future__ import annotations

from typing import Any

from hypothesis import given, settings
from hypothesis import strategies as st

from flatcraft_cad.validate.bend import load_spec, validate_bend

_SPEC: dict[str, Any] = load_spec()

_KNOWN_MATERIALS = sorted(
    {m for g in _SPEC["material_groups"].values() for m in g["members"]}
)
_MATERIALS = [*_KNOWN_MATERIALS, "unobtanium", ""]
_KNOWN_THICKNESSES = [r["thickness_mm"] for r in _SPEC["capability_matrix"]]
_THICKNESSES = [*_KNOWN_THICKNESSES, 7.0, 3.5, 0.7]
_RADII = [1.0, 2.5, 4.0, 5.0, 3.0, 6.0, 0.5]


def _should_reject(material: str, thickness: float, radius: float) -> bool:
    """Oracle, ідентичний TS shouldReject."""
    row = next(
        (r for r in _SPEC["capability_matrix"] if r["thickness_mm"] == thickness),
        None,
    )
    if row is None:
        return True
    group = _SPEC["material_groups"].get(row["group"])
    if group is not None and material not in group["members"]:
        return True
    return radius not in row["allowed_inner_radius_mm"]  # noqa: SIM103 — явність


@settings(max_examples=1000)
@given(
    material=st.sampled_from(_MATERIALS),
    thickness=st.sampled_from(_THICKNESSES),
    radius=st.sampled_from(_RADII),
)
def test_validate_bend_matrix_parity(material: str, thickness: float, radius: float) -> None:
    errors = validate_bend(
        material_code=material,
        thickness_mm=thickness,
        inner_radius_mm=radius,
        angle_deg=90,
        spec=_SPEC,
    )
    if _should_reject(material, thickness, radius):
        assert errors, (material, thickness, radius)
    else:
        assert errors == [], (material, thickness, radius, errors)
