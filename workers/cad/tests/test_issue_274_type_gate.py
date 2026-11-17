"""Issue #274: числовий параметр не того типу → 422, а не 500/200.

Регресія: прямий виклик `/export` (API-gate у Zod обійдено) з рядком, що не
розбирається як число, списком, словником, `null` чи `bool` у числовому полі
давав 500 (`float()`/порівняння без захисту у `validate/bend.py`,
`validate/perforation.py`) або мовчазний 200 (`validate/holes.py` ковтає
зіпсований отвір і просто не перевіряє решту, не повідомляючи про причину).
Новий гейт `validate/types.py` ловить це ДО решти гейтів (ADR-019 — остання
лінія оборони воркера).
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import boto3
import pytest
from fastapi.testclient import TestClient
from moto import mock_aws

from flatcraft_cad.server import app
from flatcraft_cad.validate.types import sanitize_for_gates, validate_export_types

from .test_server import (
    ENCLOSED_SHELF_VALID_PARAMS,
    PERFORATED_PANEL_VALID_PARAMS,
    VALID_PARAMS,
    Z_VALID_PARAMS,
)

TYPE_CODE = "INVALID_PARAMETER_TYPE"


@pytest.fixture(autouse=True)
def _s3_env(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    """moto — на КОЖЕН тест, не лише на валідні: на мутанті (код до 049) зіпсоване
    значення доходить до вивантаження в S3, і без mock тест ішов у справжню мережу —
    на A8 (egress за allowlist) висів до таймауту оракула (049, рецензія Flash #295)."""
    monkeypatch.delenv("S3_ENDPOINT", raising=False)
    monkeypatch.setenv("S3_ACCESS_KEY_ID", "test")
    monkeypatch.setenv("S3_SECRET_ACCESS_KEY", "test")
    monkeypatch.setenv("S3_BUCKET", "flatcraft-test")
    monkeypatch.setenv("S3_REGION", "us-east-1")
    with mock_aws():
        yield


@pytest.fixture
def aws_with_bucket() -> None:
    """Створює bucket для тестів; moto вже активний з `_s3_env`."""
    s3 = boto3.client("s3", region_name="us-east-1")
    s3.create_bucket(Bucket="flatcraft-test")


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


def _export(client: TestClient, slug: str, params: dict[str, object], t: float = 2) -> Any:
    return client.post(
        "/export",
        json={
            "template_slug": slug,
            "parameters": params,
            "thickness_mm": t,
            "material_code": "cold_rolled_steel",
        },
    )


def _codes(detail: list[dict[str, str]]) -> set[str]:
    return {e["code"] for e in detail}


class TestNeNumericTopLevelField:
    """Рядок, список, словник, null — 422 з INVALID_PARAMETER_TYPE, не 500."""

    @pytest.mark.parametrize(
        "bad",
        ["not-a-number", [1, 2], {"x": 1}, None],
        ids=["str", "list", "dict", "null"],
    )
    def test_bend_radius_mm_422_не_500(self, client: TestClient, bad: object) -> None:
        res = _export(client, "l_bracket", {**VALID_PARAMS, "bend_radius_mm": bad})
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        assert isinstance(detail, list), res.text
        assert any(e["code"] == TYPE_CODE and e["field"] == "bend_radius_mm" for e in detail)

    @pytest.mark.parametrize(
        "bad",
        ["not-a-number", [1, 2]],
        ids=["str", "list"],
    )
    def test_bend_angle_deg_422_не_500(self, client: TestClient, bad: object) -> None:
        res = _export(client, "z_bracket", {**Z_VALID_PARAMS, "bend_angle_deg": bad})
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        assert any(e["code"] == TYPE_CODE and e["field"] == "bend_angle_deg" for e in detail)


class TestBoolNeКоерситься:
    """`true`/`false` у числовому полі — помилка типу, а не 1.0/0.0 (контрприклади Argon)."""

    def test_pitch_x_mm_true_не_holes_overlap(self, client: TestClient) -> None:
        params = {**PERFORATED_PANEL_VALID_PARAMS, "pitch_x_mm": True}
        res = _export(client, "perforated_panel", params)
        assert res.status_code == 422, res.text
        codes = _codes(res.json()["detail"])
        assert TYPE_CODE in codes

    def test_bend_angle_deg_true_422_типу(self, client: TestClient) -> None:
        res = _export(client, "l_bracket", {**VALID_PARAMS, "bend_angle_deg": True})
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        assert any(e["code"] == TYPE_CODE and e["field"] == "bend_angle_deg" for e in detail)


class TestРядокЧислоПриводиться:
    """ "5"/"15" у числовому полі — валідне число, гейт діапазону рахує його як число."""

    def test_pitch_x_mm_рядком_holes_overlap_не_500(self, client: TestClient) -> None:
        res = _export(
            client, "perforated_panel", {**PERFORATED_PANEL_VALID_PARAMS, "pitch_x_mm": "5"}
        )
        assert res.status_code == 422, res.text
        assert "HOLES_OVERLAP" in _codes(res.json()["detail"])

    def test_pitch_x_mm_рядком_не_позначено_як_помилку_типу(self, client: TestClient) -> None:
        res = _export(
            client, "perforated_panel", {**PERFORATED_PANEL_VALID_PARAMS, "pitch_x_mm": "5"}
        )
        assert TYPE_CODE not in _codes(res.json()["detail"])


class TestХолостийГейтЗбережено:
    """Гейти діапазону/геометрії на валідних типах не зачеплені новим гейтом типів."""

    def test_perforated_panel_валідний_без_помилок(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        res = _export(client, "perforated_panel", PERFORATED_PANEL_VALID_PARAMS)
        assert res.status_code == 200, res.text

    def test_pitch_x_mm_5_int_holes_overlap(self, client: TestClient) -> None:
        res = _export(
            client, "perforated_panel", {**PERFORATED_PANEL_VALID_PARAMS, "pitch_x_mm": 5}
        )
        assert res.status_code == 422, res.text
        assert "HOLES_OVERLAP" in _codes(res.json()["detail"])


class TestHoleNeНечисловий:
    """Нечисловий розмір отвору в `holes[]` (l_bracket/z_bracket) — 422, не 200."""

    BAD_HOLE = {
        "leg": "A",
        "distance_from_edge_mm": 20,
        "distance_from_bend_mm": "not-a-number",
        "diameter_mm": 6,
    }

    def test_l_bracket_holes_нечислове_422(self, client: TestClient) -> None:
        res = _export(client, "l_bracket", {**VALID_PARAMS, "holes": [self.BAD_HOLE]})
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        assert any(
            e["code"] == TYPE_CODE and e["field"] == "holes.0.distance_from_bend_mm" for e in detail
        )

    def test_z_bracket_holes_null_діаметр_422(self, client: TestClient) -> None:
        hole = {
            "leg": "A",
            "distance_from_edge_mm": 20,
            "distance_from_bend_mm": 30,
            "diameter_mm": None,
        }
        res = _export(client, "z_bracket", {**Z_VALID_PARAMS, "holes": [hole]})
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        assert any(e["code"] == TYPE_CODE and e["field"] == "holes.0.diameter_mm" for e in detail)


class TestEnclosedShelfВкладені:
    """stiffening_rib/side_perforation — нечислове вкладене поле → 422 зі шляхом."""

    def test_stiffening_rib_height_mm_422(self, client: TestClient) -> None:
        res = _export(
            client,
            "enclosed_shelf",
            {**ENCLOSED_SHELF_VALID_PARAMS, "stiffening_rib": {"height_mm": "not-a-number"}},
        )
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        assert any(
            e["code"] == TYPE_CODE and e["field"] == "stiffening_rib.height_mm" for e in detail
        )

    def test_side_perforation_hole_size_mm_422(self, client: TestClient) -> None:
        bad_perforation = {
            "hole_size_mm": [1, 2],
            "pitch_x_mm": 20,
            "pitch_y_mm": 20,
            "margin_mm": 20,
        }
        res = _export(
            client,
            "enclosed_shelf",
            {**ENCLOSED_SHELF_VALID_PARAMS, "side_perforation": bad_perforation},
        )
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        assert any(
            e["code"] == TYPE_CODE and e["field"] == "side_perforation.hole_size_mm" for e in detail
        )


class TestGateCodesПоруч:
    """Помилка типу в одному полі не вимикає гейти, яким це поле не потрібне."""

    def test_material_not_allowed_поруч_з_помилкою_типу(self, client: TestClient) -> None:
        # z_bracket, t=10, stainless_304 (не в групі) + offset_mm нечисловий.
        res = client.post(
            "/export",
            json={
                "template_slug": "z_bracket",
                "parameters": {**Z_VALID_PARAMS, "offset_mm": "not-a-number"},
                "thickness_mm": 10,
                "material_code": "stainless_304",
            },
        )
        assert res.status_code == 422, res.text
        codes = _codes(res.json()["detail"])
        assert TYPE_CODE in codes
        assert "MATERIAL_NOT_ALLOWED" in codes


class TestValidateTypesUnit:
    """Юніт-тести самого гейта (без HTTP) — валідні значення не позначаються."""

    def test_валідні_params_без_помилок(self) -> None:
        assert validate_export_types("l_bracket", VALID_PARAMS) == []

    def test_відсутнє_поле_не_помилка(self) -> None:
        params = {k: v for k, v in VALID_PARAMS.items() if k != "bend_radius_mm"}
        assert validate_export_types("l_bracket", params) == []

    def test_sanitize_нейтралізує_лише_верхній_рівень(self) -> None:
        params = {**VALID_PARAMS, "bend_radius_mm": "not-a-number"}
        errors = validate_export_types("l_bracket", params)
        sanitized = sanitize_for_gates(params, errors)
        assert sanitized["bend_radius_mm"] is None
        assert sanitized["legA_mm"] == VALID_PARAMS["legA_mm"]
        assert params["bend_radius_mm"] == "not-a-number"  # оригінал не мутується
