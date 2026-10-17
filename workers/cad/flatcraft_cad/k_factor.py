"""K-фактор розгортки гиба за матеріалом (ADR-043).

Дзеркало TS `packages/cad-engine/src/k-factor.ts::computeKFactor`: той самий
`bend-machine-esi.yaml` (`load_spec` — одне джерело істини), та сама формула
K = k_factor.default_by_material[material] × ratio_correction(R/t), ті самі
межі діапазонів ([ratio_min, ratio_max) — inclusive lower) і ті самі жорсткі
помилки (ValueError) на невідомому матеріалі чи ratio поза діапазоном.

Leaf-модуль (залежить лише від `validate.bend.load_spec`) — без залежності на
`unfold.py`/`templates/*`, щоб і `server.py`, і `validate/sheet.py` могли його
використати без циклічного імпорту. `load_spec` імпортується лениво усередині
функції (не на рівні модуля): `flatcraft_cad.validate.bend` — підмодуль пакета
`flatcraft_cad.validate`, тож імпорт на рівні модуля запускає
`validate/__init__.py`, який імпортує `validate/sheet.py`, а той імпортує
ЦЕЙ модуль — цикл (той самий паттерн lazy-імпорту, що й
`unfold.py::_enclosed_shelf_side_holes`, уже є в кодовій базі).
"""

from __future__ import annotations

from typing import Any


def compute_k_factor(
    material_code: str,
    thickness_mm: float,
    inner_radius_mm: float,
    spec: dict[str, Any] | None = None,
) -> float:
    """K = base_K(material) × multiplier(R/t). Кидає ValueError на невалідному вході."""
    if thickness_mm <= 0:
        raise ValueError(f"compute_k_factor: thickness_mm must be > 0, got {thickness_mm}")
    if inner_radius_mm < 0:
        raise ValueError(f"compute_k_factor: inner_radius_mm must be >= 0, got {inner_radius_mm}")

    if spec is None:
        from flatcraft_cad.validate.bend import load_spec  # noqa: PLC0415

        spec = load_spec()
    k_factor_spec = spec["k_factor"]

    base_k = k_factor_spec["default_by_material"].get(material_code)
    if base_k is None:
        available = ", ".join(k_factor_spec["default_by_material"])
        raise ValueError(
            f'compute_k_factor: no base K-factor for material "{material_code}". '
            f"Available: {available}"
        )

    ratio = inner_radius_mm / thickness_mm
    correction = next(
        (c for c in k_factor_spec["ratio_correction"] if c["ratio_min"] <= ratio < c["ratio_max"]),
        None,
    )
    if correction is None:
        raise ValueError(
            f"compute_k_factor: ratio R/S = {ratio:.3f} is outside any configured "
            "ratio_correction range"
        )

    return float(base_k) * float(correction["multiplier"])
