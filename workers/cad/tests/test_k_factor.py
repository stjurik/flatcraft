"""Тести `compute_k_factor` (ADR-043, issue #246).

Дзеркало TS `packages/cad-engine/src/k-factor.test.ts::computeKFactor` — та
сама `bend-machine-esi.yaml`, та сама формула K = base(material)×multiplier(R/t).
"""

from __future__ import annotations

import pytest

from flatcraft_cad.k_factor import compute_k_factor
from flatcraft_cad.validate.bend import load_spec

SPEC = load_spec()


class TestComputeKFactorRanges:
    """Кожен материал YAML, по одному представнику на кожен з 3 діапазонів
    ratio_correction ([0,1), [1,3), [3,999)) — K = base × multiplier."""

    @pytest.mark.parametrize(
        ("material_code", "t", "r", "expected_k"),
        [
            # [0, 1) → multiplier 0.85
            ("cold_rolled_steel", 2.0, 1.0, 0.40 * 0.85),
            ("hot_rolled_steel", 4.0, 1.0, 0.42 * 0.85),
            ("stainless_304", 2.0, 0.5, 0.45 * 0.85),
            # [1, 3) → multiplier 1.00
            ("galvanized_steel", 2.0, 2.0, 0.40 * 1.00),
            ("aluminum_5754", 2.0, 2.5, 0.33 * 1.00),
            ("brass", 2.0, 4.0, 0.38 * 1.00),
            # [3, 999) → multiplier 1.10
            ("stainless_430", 1.0, 4.0, 0.44 * 1.10),
            ("aluminum_amg3", 2.0, 10.0, 0.33 * 1.10),
            ("copper", 1.0, 3.0, 0.38 * 1.10),
        ],
    )
    def test_base_times_multiplier(
        self, material_code: str, t: float, r: float, expected_k: float
    ) -> None:
        assert compute_k_factor(material_code, t, r, SPEC) == pytest.approx(expected_k, abs=1e-9)

    def test_межа_ratio_1_0_верхній_діапазон(self) -> None:
        """ratio=R/t рівно 1.0 → [1, 3) (inclusive lower), НЕ [0, 1)."""
        k = compute_k_factor("cold_rolled_steel", 2.0, 2.0, SPEC)
        assert k == pytest.approx(0.40, abs=1e-9)
        assert k > 0.34  # якби попало у [0,1): 0.40*0.85=0.34

    def test_межа_ratio_3_0_верхній_діапазон(self) -> None:
        """ratio=R/t рівно 3.0 → [3, 999) (inclusive lower), НЕ [1, 3)."""
        k = compute_k_factor("cold_rolled_steel", 2.0, 6.0, SPEC)
        assert k == pytest.approx(0.40 * 1.10, abs=1e-9)

    def test_невідомий_материал_кидає(self) -> None:
        with pytest.raises(ValueError, match="material"):
            compute_k_factor("unobtanium", 2.0, 2.0, SPEC)

    def test_нульова_товщина_кидає(self) -> None:
        with pytest.raises(ValueError, match="thickness_mm"):
            compute_k_factor("cold_rolled_steel", 0.0, 2.0, SPEC)

    def test_ratio_поза_діапазоном_кидає(self) -> None:
        with pytest.raises(ValueError, match="ratio"):
            compute_k_factor("cold_rolled_steel", 1.0, 1000.0, SPEC)


# Паритет TS↔Python (issue #246): ОДНАКОВІ числа дзеркалить
# `packages/cad-engine/src/k-factor.test.ts` (`it.each` блок після «межа
# діапазону»). Обидва файли рахують (материал, t, R) незалежно — якщо один з
# них розійдеться з bend-machine-esi.yaml, збіжність зникне.
PARITY_TABLE = [
    ("cold_rolled_steel", 2.0, 1.0, 0.34),
    ("hot_rolled_steel", 2.0, 2.5, 0.42),
    ("galvanized_steel", 1.0, 4.0, 0.44),
    ("stainless_304", 2.0, 2.0, 0.45),
    ("stainless_430", 2.5, 1.0, 0.374),
    ("aluminum_5754", 2.0, 10.0, 0.363),
    ("aluminum_amg3", 4.0, 4.0, 0.33),
    ("copper", 1.0, 0.5, 0.323),
    ("brass", 2.0, 6.0, 0.418),
]


@pytest.mark.parametrize(("material_code", "t", "r", "expected_k"), PARITY_TABLE)
def test_parity_table(material_code: str, t: float, r: float, expected_k: float) -> None:
    assert compute_k_factor(material_code, t, r, SPEC) == pytest.approx(expected_k, abs=1e-9)
