"""Bend allowance (BA) — довжина матеріалу по нейтральній осі гиба.

Виокремлено з `unfold.py` в окремий leaf-модуль (без залежностей на
`templates/*`), щоб `validate/sheet.py` міг використати ОДНУ й ту саму
формулу без циклічного імпорту (`unfold.py` → `templates/*` →
`templates/base.py` → `validate/profile.py` → `validate/__init__.py` →
`validate/sheet.py` → `unfold.py`). `unfold.py` ре-експортує цю функцію
для сумісності з існуючим імпортом (`from flatcraft_cad.unfold import
compute_bend_allowance`).

Дзеркало TS `packages/cad-engine/src/k-factor.ts::computeBendAllowanceMm`.
"""

from __future__ import annotations

import math


def compute_bend_allowance(
    angle_deg: float,
    inner_radius_mm: float,
    thickness_mm: float,
    k_factor: float,
) -> float:
    """BA = (π/180) · angle · (R + K·t).

    Невалідні діапазони — ValueError (мають відсіюватись TS-валідатором
    до виклику воркера).
    """
    if not 0.0 < angle_deg <= 180.0:
        raise ValueError(f"angle_deg must be in (0, 180]; got {angle_deg}")
    if inner_radius_mm < 0.0:
        raise ValueError(f"inner_radius_mm must be >= 0; got {inner_radius_mm}")
    if thickness_mm <= 0.0:
        raise ValueError(f"thickness_mm must be > 0; got {thickness_mm}")
    if not 0.0 < k_factor <= 1.0:
        raise ValueError(f"k_factor must be in (0, 1]; got {k_factor}")

    return math.radians(angle_deg) * (inner_radius_mm + k_factor * thickness_mm)
