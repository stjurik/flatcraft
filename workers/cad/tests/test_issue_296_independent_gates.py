"""Тести issue #296: зіпсоване поле (None після `sanitize_for_gates`) не
ховає коди НЕЗАЛЕЖНИХ гейтів воркера.

Регресія на main: один `try/except` на всю перевірку (`validate/profile.py`,
`validate/sheet.py`) чи спільний `radius is None or angle is None` бейл
(`validate/bend.py`) гасив УСІ помилки шаблону, щойно одне поле не
конвертувалось у `float` — користувач бачив лише `INVALID_PARAMETER_TYPE`
замість і цього коду, і реального порушення в іншому полі. `_params_with_defaults`
(`server.py`) теж повертав сирі parameters без жодного Pydantic-дефолту, коли
модель не валідувалась з будь-якої причини — відсутній `bend_angle_deg`
лишався невидимим для `validate/bend.py`.

Якщо реалізацію (`flatcraft_cad/*.py`) повернути в стан main, цей файл має
почервоніти.
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import boto3
import pytest
from fastapi.testclient import TestClient
from moto import mock_aws

from flatcraft_cad.server import app

from .test_server import (
    CORNER_VALID_PARAMS,
    ENCLOSED_SHELF_VALID_PARAMS,
    PERFORATED_PANEL_VALID_PARAMS,
    VALID_PARAMS,
    WALL_SHELF_VALID_PARAMS,
    Z_VALID_PARAMS,
)


@pytest.fixture(autouse=True)
def _s3(monkeypatch: pytest.MonkeyPatch) -> Iterator[None]:
    monkeypatch.delenv("S3_ENDPOINT", raising=False)
    monkeypatch.setenv("S3_ACCESS_KEY_ID", "test")
    monkeypatch.setenv("S3_SECRET_ACCESS_KEY", "test")
    monkeypatch.setenv("S3_BUCKET", "flatcraft-test")
    monkeypatch.setenv("S3_REGION", "us-east-1")
    with mock_aws():
        boto3.client("s3", region_name="us-east-1").create_bucket(Bucket="flatcraft-test")
        yield


@pytest.fixture
def client() -> TestClient:
    return TestClient(app, raise_server_exceptions=False)


def _export(
    client: TestClient,
    slug: str,
    params: dict[str, Any],
    t: float,
    material: str = "cold_rolled_steel",
) -> tuple[int, list[dict[str, str]]]:
    res = client.post(
        "/export",
        json={
            "template_slug": slug,
            "parameters": params,
            "thickness_mm": t,
            "material_code": material,
        },
    )
    assert res.status_code != 500, res.text
    detail = res.json().get("detail")
    errors = detail if res.status_code == 422 and isinstance(detail, list) else []
    return res.status_code, errors


def _codes_and_fields(errors: list[dict[str, str]]) -> set[tuple[str, str]]:
    return {(e["code"], e["field"]) for e in errors}


# ---------------------------------------------------------------------------
# A. validate/profile.py — кожна полиця/ребро/offset незалежна.
# ---------------------------------------------------------------------------


class TestProfileIndependentOfCorruptedField:
    def test_l_bracket_legb_зіпсований_не_ховає_lega(self, client: TestClient) -> None:
        ctrl = {**VALID_PARAMS, "legA_mm": 3}
        status, errors = _export(client, "l_bracket", ctrl, 2)
        assert status == 422
        assert ("LEG_TOO_SHORT", "legA") in _codes_and_fields(errors)

        bad = {**ctrl, "legB_mm": "nan"}
        status, errors = _export(client, "l_bracket", bad, 2)
        assert status == 422
        pairs = _codes_and_fields(errors)
        assert ("INVALID_PARAMETER_TYPE", "legB_mm") in pairs
        assert ("LEG_TOO_SHORT", "legA") in pairs

    def test_corner_angle_legb_зіпсований_не_ховає_lega(self, client: TestClient) -> None:
        ctrl = {**CORNER_VALID_PARAMS, "legA_mm": 3}
        bad = {**ctrl, "legB_mm": "inf"}
        status, errors = _export(client, "corner_angle", bad, 2)
        assert status == 422
        pairs = _codes_and_fields(errors)
        assert ("INVALID_PARAMETER_TYPE", "legB_mm") in pairs
        assert ("LEG_TOO_SHORT", "legA") in pairs

    def test_z_bracket_bottom_зіпсований_не_ховає_top(self, client: TestClient) -> None:
        ctrl = {**Z_VALID_PARAMS, "top_flange_mm": 4}
        bad = {**ctrl, "bottom_flange_mm": "nan"}
        status, errors = _export(client, "z_bracket", bad, 2)
        assert status == 422
        pairs = _codes_and_fields(errors)
        assert ("INVALID_PARAMETER_TYPE", "bottom_flange_mm") in pairs
        assert ("FLANGE_TOO_SHORT", "top_flange") in pairs

    def test_wall_shelf_shelf_depth_зіпсований_не_ховає_back_height(
        self, client: TestClient
    ) -> None:
        ctrl = {**WALL_SHELF_VALID_PARAMS, "back_height_mm": 4}
        bad = {**ctrl, "shelf_depth_mm": "nan"}
        status, errors = _export(client, "wall_shelf", bad, 2)
        assert status == 422
        pairs = _codes_and_fields(errors)
        assert ("INVALID_PARAMETER_TYPE", "shelf_depth_mm") in pairs
        assert ("FLANGE_TOO_SHORT", "back_height") in pairs

    def test_perforated_panel_length_зіпсований_не_ховає_rib_height(
        self, client: TestClient
    ) -> None:
        ctrl = {**PERFORATED_PANEL_VALID_PARAMS, "rib_height_mm": 4}
        bad = {**ctrl, "length_mm": "nan"}
        status, errors = _export(client, "perforated_panel", bad, 2)
        assert status == 422
        pairs = _codes_and_fields(errors)
        assert ("INVALID_PARAMETER_TYPE", "length_mm") in pairs
        assert ("FLANGE_TOO_SHORT", "rib_height") in pairs

    def test_зворотне_lega_зіпсований_не_вигадує_leg_too_short_на_lega(
        self, client: TestClient
    ) -> None:
        """legA_mm саме той параметр, від якого залежить LEG_TOO_SHORT(legA) —
        при його зіпсованості код НЕ має вигадуватись."""
        bad = {**VALID_PARAMS, "legA_mm": "nan"}
        status, errors = _export(client, "l_bracket", bad, 2)
        assert status == 422
        pairs = _codes_and_fields(errors)
        assert ("LEG_TOO_SHORT", "legA") not in pairs
        assert any(code == "INVALID_PARAMETER_TYPE" for code, _ in pairs)


# ---------------------------------------------------------------------------
# B. validate/sheet.py — вісь ширини і вісь довжини вздовж профілю незалежні.
# ---------------------------------------------------------------------------

BIG_RADIUS = {"bend_radius_mm": 5}  # t=8: max_bend_length 1000, дозволений радіус лише 5


class TestSheetAxisIndependentOfCorruptedField:
    def test_z_bracket_width_зіпсований_не_ховає_довжину_профілю(self, client: TestClient) -> None:
        ctrl = {
            **Z_VALID_PARAMS,
            "top_flange_mm": 400,
            "bottom_flange_mm": 400,
            "offset_mm": 250,
            **BIG_RADIUS,
        }
        status, errors = _export(client, "z_bracket", ctrl, 8)
        assert status == 422
        assert ("SHEET_EXCEEDS_MAX_LENGTH", "width_mm") in _codes_and_fields(errors)

        bad = {**ctrl, "width_mm": "nan"}
        status, errors = _export(client, "z_bracket", bad, 8)
        assert status == 422
        pairs = _codes_and_fields(errors)
        assert ("INVALID_PARAMETER_TYPE", "width_mm") in pairs
        assert ("SHEET_EXCEEDS_MAX_LENGTH", "width_mm") in pairs

    def test_wall_shelf_width_зіпсований_не_ховає_довжину_профілю(self, client: TestClient) -> None:
        ctrl = {
            **WALL_SHELF_VALID_PARAMS,
            "back_height_mm": 500,
            "shelf_depth_mm": 500,
            "front_lip_mm": 100,
            **BIG_RADIUS,
        }
        bad = {**ctrl, "width_mm": "nan"}
        status, errors = _export(client, "wall_shelf", bad, 8)
        assert status == 422
        pairs = _codes_and_fields(errors)
        assert ("INVALID_PARAMETER_TYPE", "width_mm") in pairs
        assert ("SHEET_EXCEEDS_MAX_LENGTH", "width_mm") in pairs

    def test_perforated_panel_width_зіпсований_не_ховає_довжину(self, client: TestClient) -> None:
        ctrl = {
            **PERFORATED_PANEL_VALID_PARAMS,
            "length_mm": 950,
            "rib_height_mm": 40,
            **BIG_RADIUS,
        }
        bad = {**ctrl, "width_mm": "nan"}
        status, errors = _export(client, "perforated_panel", bad, 8)
        assert status == 422
        pairs = _codes_and_fields(errors)
        assert ("INVALID_PARAMETER_TYPE", "width_mm") in pairs
        assert ("SHEET_EXCEEDS_MAX_LENGTH", "width_mm") in pairs

    def test_enclosed_shelf_stiffening_rib_зіпсований_не_ховає_ширину(
        self, client: TestClient
    ) -> None:
        ctrl = {
            **ENCLOSED_SHELF_VALID_PARAMS,
            "width_mm": 900,
            "depth_mm": 200,
            **BIG_RADIUS,
        }
        status, errors = _export(client, "enclosed_shelf", ctrl, 8)
        assert status == 422
        assert ("SHEET_EXCEEDS_MAX_LENGTH", "width_mm") in _codes_and_fields(errors)

        bad = {**ctrl, "stiffening_rib": {"height_mm": "nan"}}
        status, errors = _export(client, "enclosed_shelf", bad, 8)
        assert status == 422
        pairs = _codes_and_fields(errors)
        assert ("INVALID_PARAMETER_TYPE", "stiffening_rib.height_mm") in pairs
        assert ("SHEET_EXCEEDS_MAX_LENGTH", "width_mm") in pairs

    def test_зворотне_rib_height_не_вигадує_flange_too_short(self, client: TestClient) -> None:
        """rib_height_mm = 10 з дефолтним радіусом 2.5 ДАЄ FLANGE_TOO_SHORT
        (10 > t+r=10.5 — ні, 10<=10.5 → fires), але якщо сам bend_radius_mm
        зіпсований, дефолт 2.5 НЕ повинен застосовуватись (ключ присутній)."""
        bad = {
            **PERFORATED_PANEL_VALID_PARAMS,
            "rib_height_mm": 10,
            "bend_radius_mm": "nan",
        }
        status, errors = _export(client, "perforated_panel", bad, 8)
        assert status == 422
        pairs = _codes_and_fields(errors)
        assert ("FLANGE_TOO_SHORT", "rib_height") not in pairs
        assert any(code == "INVALID_PARAMETER_TYPE" for code, _ in pairs)


# ---------------------------------------------------------------------------
# C. validate/bend.py — радіус і кут незалежні.
# ---------------------------------------------------------------------------


class TestBendRadiusAngleIndependent:
    def test_l_bracket_radius_not_allowed_не_ховається_зіпсованим_кутом(
        self, client: TestClient
    ) -> None:
        ctrl = {**VALID_PARAMS, "bend_radius_mm": 5}
        bad = {**ctrl, "bend_angle_deg": "nan"}
        status, errors = _export(client, "l_bracket", bad, 2)
        assert status == 422
        pairs = _codes_and_fields(errors)
        assert ("INVALID_PARAMETER_TYPE", "bend_angle_deg") in pairs
        assert ("RADIUS_NOT_ALLOWED", "bend_radius_mm") in pairs

    def test_z_bracket_angle_not_allowed_не_ховається_зіпсованим_радіусом(
        self, client: TestClient
    ) -> None:
        ctrl = {**Z_VALID_PARAMS, "bend_angle_deg": 37}
        bad = {**ctrl, "bend_radius_mm": "nan"}
        status, errors = _export(client, "z_bracket", bad, 2)
        assert status == 422
        pairs = _codes_and_fields(errors)
        assert ("INVALID_PARAMETER_TYPE", "bend_radius_mm") in pairs
        assert ("ANGLE_NOT_ALLOWED", "bend_angle_deg") in pairs

    def test_enclosed_shelf_radius_not_allowed_без_bend_angle_deg_і_з_зіпсованою_перфорацією(
        self, client: TestClient
    ) -> None:
        """bend_angle_deg відсутній у payload (не зіпсований) — Pydantic-
        дефолт 90 має підставитись `_params_with_defaults` навіть коли модель
        не валідувалась з іншої причини (зіпсоване side_perforation)."""
        ctrl = {
            k: v
            for k, v in {**ENCLOSED_SHELF_VALID_PARAMS, "bend_radius_mm": 1.0}.items()
            if k != "bend_angle_deg"
        }
        bad = {
            **ctrl,
            "side_perforation": {
                "hole_size_mm": "nan",
                "pitch_x_mm": 20,
                "pitch_y_mm": 20,
                "margin_mm": 20,
            },
        }
        status, errors = _export(client, "enclosed_shelf", bad, 4)
        assert status == 422
        pairs = _codes_and_fields(errors)
        assert ("INVALID_PARAMETER_TYPE", "side_perforation.hole_size_mm") in pairs
        assert ("RADIUS_NOT_ALLOWED", "bend_radius_mm") in pairs


# ---------------------------------------------------------------------------
# D. Валідні параметри — усі шаблони все ще повертають 200.
# ---------------------------------------------------------------------------


class TestValidParametersStillSucceed:
    @pytest.mark.parametrize(
        ("slug", "params"),
        [
            ("l_bracket", VALID_PARAMS),
            ("z_bracket", Z_VALID_PARAMS),
            ("corner_angle", CORNER_VALID_PARAMS),
            ("wall_shelf", WALL_SHELF_VALID_PARAMS),
            ("perforated_panel", PERFORATED_PANEL_VALID_PARAMS),
            ("enclosed_shelf", ENCLOSED_SHELF_VALID_PARAMS),
        ],
    )
    def test_200(self, client: TestClient, slug: str, params: dict[str, Any]) -> None:
        status, _ = _export(client, slug, params, 2)
        assert status == 200
