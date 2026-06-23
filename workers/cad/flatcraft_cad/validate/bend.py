"""Parity bend-валідатор (Hotfix 2.10.e, ADR-019).

Дзеркало TS `packages/cad-engine/src/validators/bend.ts`: читає той самий
`bend-machine-esi.yaml` і перевіряє, що радіус/кут/товщина гиба допустимі
саме для (матеріал, товщина) за матрицею — а не лише з глобального набору.

Це остання лінія оборони у воркері: навіть якщо API-gate обійдено
(прямий виклик /export, майбутній BullMQ-producer без gate тощо), воркер
відмовляє ДО CAD-операції та запису у R2.

Матеріал: API strip'ить `material_code` перед forward (ADR-018), тож воркер
зазвичай валідує без матеріалу (material_code=None) — radius/angle/thickness
матеріало-незалежні. Перевірка material-group лишається у API-gate, де
material_code присутній. Функція приймає material_code опційно для повного
паритету (використовується property-based тестами).
"""

from __future__ import annotations

import os
from dataclasses import asdict, dataclass
from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml


@dataclass(frozen=True)
class BendError:
    """Один елемент 422-detail. `code` збігається з RFC 9457 кодами API-gate."""

    code: str
    field: str
    detail: str


def _spec_path() -> Path:
    """Шлях до bend-machine-esi.yaml.

    У контейнері — `BEND_MACHINE_SPEC_PATH` (cad-worker.Dockerfile копіює YAML
    у /app/data і виставляє env). У dev/tests — repo-path до єдиного джерела
    у packages/cad-engine/data (CLAUDE.md §"одне джерело істини").
    """
    env_path = os.environ.get("BEND_MACHINE_SPEC_PATH")
    if env_path:
        return Path(env_path)
    # bend.py → validate → flatcraft_cad → cad → workers → <repo-root>
    repo_root = Path(__file__).resolve().parents[4]
    return repo_root / "packages" / "cad-engine" / "data" / "bend-machine-esi.yaml"


@lru_cache(maxsize=1)
def load_spec() -> dict[str, Any]:
    """Парсить YAML один раз на процес (lru_cache)."""
    with _spec_path().open(encoding="utf-8") as fh:
        spec: dict[str, Any] = yaml.safe_load(fh)
    return spec


def _radius_hint(got: float, allowed: list[float], thickness_mm: float) -> str:
    """Дружня підказка для недопустимого радіуса (паритет з API-gate)."""
    ordered = sorted(allowed)
    lo, hi = ordered[0], ordered[-1]
    listed = ", ".join(f"{r:g}" for r in ordered)
    if got < lo:
        return (
            f"Збільшіть радіус гибки: для товщини {thickness_mm:g} мм мінімальний "
            f"радіус {lo:g} мм (дозволено: {listed} мм)."
        )
    if got > hi:
        return (
            f"Зменшіть радіус гибки: для товщини {thickness_mm:g} мм максимальний "
            f"радіус {hi:g} мм (дозволено: {listed} мм)."
        )
    return f"Оберіть дозволений радіус гибки для товщини {thickness_mm:g} мм: {listed} мм."


def validate_bend(
    *,
    material_code: str | None,
    thickness_mm: float,
    inner_radius_mm: float,
    angle_deg: float,
    spec: dict[str, Any] | None = None,
) -> list[BendError]:
    """Перевіряє один гиб проти матриці. Порожній список → валідно.

    Дзеркалить порядок і логіку TS `validateBend`:
      1. row-lookup за товщиною (немає → THICKNESS_NOT_SUPPORTED, рання відмова);
      2. material-group (лише якщо material_code задано);
      3. allowed_inner_radius_mm для саме цієї товщини;
      4. allowed_angles_deg (global).
    """
    spec = spec if spec is not None else load_spec()
    matrix: list[dict[str, Any]] = spec["capability_matrix"]
    row = next((r for r in matrix if r["thickness_mm"] == thickness_mm), None)
    if row is None:
        return [
            BendError(
                code="THICKNESS_NOT_SUPPORTED",
                field="thickness_mm",
                detail=f"Товщина {thickness_mm} мм не підтримується.",
            )
        ]

    errors: list[BendError] = []

    if material_code is not None:
        group = spec["material_groups"].get(row["group"])
        if group is not None and material_code not in group["members"]:
            errors.append(
                BendError(
                    code="MATERIAL_NOT_ALLOWED",
                    field="material_code",
                    detail=(
                        f"Матеріал {material_code} не підтримується для гиба "
                        f"товщиною {thickness_mm} мм."
                    ),
                )
            )

    allowed_radii: list[float] = row["allowed_inner_radius_mm"]
    if inner_radius_mm not in allowed_radii:
        errors.append(
            BendError(
                code="RADIUS_NOT_ALLOWED",
                field="bend_radius_mm",
                detail=_radius_hint(inner_radius_mm, allowed_radii, thickness_mm),
            )
        )

    allowed_angles: list[float] = spec["global"]["allowed_angles_deg"]
    if angle_deg not in allowed_angles:
        errors.append(
            BendError(
                code="ANGLE_NOT_ALLOWED",
                field="bend_angle_deg",
                detail=f"Кут {angle_deg}° недопустимий. Дозволено: {allowed_angles}.",
            )
        )

    return errors


def validate_export(
    template_slug: str,
    parameters: dict[str, Any],
    thickness_mm: float,
    material_code: str | None = None,
) -> list[dict[str, str]]:
    """Валідація гиба для export-payload. Повертає JSON-готовий список dict-ів.

    Шаблони без гибів (perforated_panel) → []. Усі гиби в межах шаблону мають
    однаковий (радіус, кут), тож одного виклику validate_bend достатньо.
    """
    if template_slug in ("perforated_panel", "perforated_panel_square"):
        return []

    radius = parameters.get("bend_radius_mm")
    angle = parameters.get("bend_angle_deg")
    if radius is None or angle is None:
        # Відсутні bend-поля — Pydantic-валідація шаблону відмовить пізніше.
        return []

    errors = validate_bend(
        material_code=material_code,
        thickness_mm=thickness_mm,
        inner_radius_mm=float(radius),
        angle_deg=float(angle),
    )
    return [asdict(e) for e in errors]
