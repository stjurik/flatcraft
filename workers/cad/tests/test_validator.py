"""Parity bend-validator на Python-боці — Hotfix 2.10.e.

Інваріант CLAUDE.md §7 п.2: радіус гиба має бути допустимим саме для
(матеріал, товщина) за матрицею `bend-machine-esi.yaml`. До цього фіксу
Python-сервер перевіряв лише глобальний набір {1,2.5,4,5}, тому Z-bracket
з t=5 + R=2.5 проскакував (для t=5 матриця дозволяє лише {4.0, 5.0}).

Цей файл — остання лінія оборони (defense-in-depth): навіть якщо API-gate
обійдено, воркер мусить відмовити ДО будь-якої CAD-операції / запису у R2.
"""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from flatcraft_cad.server import app

Z_VALID_PARAMS: dict[str, object] = {
    "top_flange_mm": 60,
    "bottom_flange_mm": 60,
    "offset_mm": 40,
    "bend_radius_mm": 2.5,
    "bend_angle_deg": 90,
    "width_mm": 100,
    "holes": [],
}


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


def test_export_z_bracket_t5_r2_5_must_fail(client: TestClient) -> None:
    """Z-bracket t=5 + R=2.5 → 422 RADIUS_NOT_ALLOWED, без створення артефактів.

    Валідація має спрацювати ДО S3-стадії — тому тест не виставляє S3-env:
    якщо валідатор пропускає, код доходить до boto3 і падає на KeyError
    (а не на чистих 422), що теж робить тест червоним до фіксу.
    """
    resp = client.post(
        "/export",
        json={
            "template_slug": "z_bracket",
            "parameters": {**Z_VALID_PARAMS, "bend_radius_mm": 2.5},
            "thickness_mm": 5.0,
        },
    )
    assert resp.status_code == 422, resp.text
    assert "RADIUS_NOT_ALLOWED" in resp.text
