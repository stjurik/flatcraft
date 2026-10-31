"""Issue #274, доробка 049 (рецензія Flash на PR #287): число — лише
СКІНЧЕННЕ, а контейнери (`holes`/`side_perforation`/`stiffening_rib`) —
правильної форми.

`5c2703f` (PR #287) закрив рядок/список/словник/`null`/`bool` у числовому
полі, але лишив три дірки (контрприклади Flash):

1. `float("nan")`/`float("inf")`/`float("-inf")` НЕ кидають винятку, а
   Python JSON-парсер за замовчуванням пропускає літерали
   `NaN`/`Infinity`/`-Infinity` без помилки — такі значення мовчки проходили
   type-гейт як «число».
2. `holes` не списком (рядок/число/словник) чи елементом не-об'єктом,
   `side_perforation`/`stiffening_rib` не об'єктом — гейт не перевіряв ФОРМУ
   контейнера взагалі, лише типи числових полів УСЕРЕДИНІ (якщо контейнер уже
   виявився потрібної форми).
3. `thickness_mm` (корінь тіла запиту, не `parameters`) — Pydantic коерсує
   `bool` у `1.0`/`0.0`, а JSON-літерал `NaN`/`Infinity` там коректно
   провалює `gt`/`le`-обмеження, але відповідь 422 з таким значенням у
   `detail` сама не серіалізується (Starlette `allow_nan=False`) → 500.

Усі тести тут мають почервоніти на `5c2703f` (до доробки 049).
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
    CORNER_VALID_PARAMS,
    ENCLOSED_SHELF_VALID_PARAMS,
    PERFORATED_PANEL_VALID_PARAMS,
    VALID_PARAMS,
    WALL_SHELF_VALID_PARAMS,
    Z_VALID_PARAMS,
)

TYPE_CODE = "INVALID_PARAMETER_TYPE"
NONFINITE = ["nan", "inf", "-inf", "NaN", "Infinity", "-Infinity"]

GOOD_HOLE = {
    "leg": "A",
    "distance_from_edge_mm": 20,
    "distance_from_bend_mm": 20,
    "diameter_mm": 6,
}


@pytest.fixture(autouse=True)
def _s3_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("S3_ENDPOINT", raising=False)
    monkeypatch.setenv("S3_ACCESS_KEY_ID", "test")
    monkeypatch.setenv("S3_SECRET_ACCESS_KEY", "test")
    monkeypatch.setenv("S3_BUCKET", "flatcraft-test")
    monkeypatch.setenv("S3_REGION", "us-east-1")


@pytest.fixture
def aws_with_bucket() -> Iterator[None]:
    with mock_aws():
        s3 = boto3.client("s3", region_name="us-east-1")
        s3.create_bucket(Bucket="flatcraft-test")
        yield


@pytest.fixture
def client() -> TestClient:
    return TestClient(app, raise_server_exceptions=False)


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


def _raw(client: TestClient, body: str) -> Any:
    return client.post("/export", content=body, headers={"content-type": "application/json"})


def _codes(detail: list[dict[str, str]]) -> set[str]:
    return {e["code"] for e in detail}


def _fields_by_code(detail: list[dict[str, str]], code: str) -> set[str]:
    return {e["field"] for e in detail if e["code"] == code}


class TestНескінченнеУВерхньомуПолі:
    """NaN/Infinity (рядком, будь-яким регістром) у числовому полі верхнього
    рівня — 422 INVALID_PARAMETER_TYPE, не мовчазне «число», для КОЖНОГО
    шаблону (включно з corner_angle/wall_shelf, яких у test_issue_274_type_gate
    немає взагалі)."""

    @pytest.mark.parametrize("bad", NONFINITE)
    def test_l_bracket_bend_radius_mm(self, client: TestClient, bad: str) -> None:
        res = _export(client, "l_bracket", {**VALID_PARAMS, "bend_radius_mm": bad})
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        assert "bend_radius_mm" in _fields_by_code(detail, TYPE_CODE), detail
        assert _codes(detail) == {TYPE_CODE}, detail

    @pytest.mark.parametrize("bad", NONFINITE)
    def test_z_bracket_offset_mm(self, client: TestClient, bad: str) -> None:
        res = _export(client, "z_bracket", {**Z_VALID_PARAMS, "offset_mm": bad})
        assert res.status_code == 422, res.text
        assert "offset_mm" in _fields_by_code(res.json()["detail"], TYPE_CODE)

    @pytest.mark.parametrize("bad", NONFINITE)
    def test_corner_angle_hole_margin_mm(self, client: TestClient, bad: str) -> None:
        res = _export(client, "corner_angle", {**CORNER_VALID_PARAMS, "hole_margin_mm": bad})
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        assert "hole_margin_mm" in _fields_by_code(detail, TYPE_CODE), detail
        assert _codes(detail) == {TYPE_CODE}, detail

    @pytest.mark.parametrize("bad", NONFINITE)
    def test_wall_shelf_front_lip_mm(self, client: TestClient, bad: str) -> None:
        res = _export(client, "wall_shelf", {**WALL_SHELF_VALID_PARAMS, "front_lip_mm": bad})
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        assert "front_lip_mm" in _fields_by_code(detail, TYPE_CODE), detail
        assert _codes(detail) == {TYPE_CODE}, detail

    @pytest.mark.parametrize("bad", NONFINITE)
    def test_perforated_panel_pitch_x_mm(self, client: TestClient, bad: str) -> None:
        res = _export(
            client, "perforated_panel", {**PERFORATED_PANEL_VALID_PARAMS, "pitch_x_mm": bad}
        )
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        assert "pitch_x_mm" in _fields_by_code(detail, TYPE_CODE), detail
        assert _codes(detail) == {TYPE_CODE}, detail

    @pytest.mark.parametrize("bad", NONFINITE)
    def test_enclosed_shelf_width_mm(self, client: TestClient, bad: str) -> None:
        res = _export(client, "enclosed_shelf", {**ENCLOSED_SHELF_VALID_PARAMS, "width_mm": bad})
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        assert "width_mm" in _fields_by_code(detail, TYPE_CODE), detail
        assert _codes(detail) == {TYPE_CODE}, detail

    @pytest.mark.parametrize("lit", ["NaN", "Infinity", "-Infinity"])
    def test_json_літерал_не_лише_рядок(self, client: TestClient, lit: str) -> None:
        """Той самий дефект і без лапок — JSON-парсер Python пропускає ці
        літерали без помилки, значення доходить як справжній python float."""
        body = (
            '{"template_slug":"l_bracket","thickness_mm":2,'
            '"material_code":"cold_rolled_steel","parameters":'
            f'{{"legA_mm":{lit},"legB_mm":40,"width_mm":30,'
            '"bend_radius_mm":2.5,"bend_angle_deg":90}}'
        )
        res = _raw(client, body)
        assert res.status_code == 422, res.text
        assert "legA_mm" in _fields_by_code(res.json()["detail"], TYPE_CODE), res.text


class TestНескінченнеУВкладеномуОтворі:
    """holes[].distance_from_bend_mm/diameter_mm — NaN/Infinity — 422,
    а не мовчазний 200 (holes.py й раніше мав isfinite-перевірку, але
    гейт типів її не мав — отвір проходив як «число»)."""

    @pytest.mark.parametrize(
        "field", ["distance_from_edge_mm", "distance_from_bend_mm", "diameter_mm"]
    )
    @pytest.mark.parametrize("bad", NONFINITE)
    def test_l_bracket(self, client: TestClient, field: str, bad: str) -> None:
        hole = {**GOOD_HOLE, field: bad}
        res = _export(client, "l_bracket", {**VALID_PARAMS, "holes": [hole]})
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        assert f"holes.0.{field}" in _fields_by_code(detail, TYPE_CODE), detail
        assert _codes(detail) == {TYPE_CODE}, detail

    @pytest.mark.parametrize("bad", NONFINITE)
    def test_z_bracket(self, client: TestClient, bad: str) -> None:
        hole = {**GOOD_HOLE, "distance_from_bend_mm": bad}
        res = _export(client, "z_bracket", {**Z_VALID_PARAMS, "holes": [hole]})
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        assert "holes.0.distance_from_bend_mm" in _fields_by_code(detail, TYPE_CODE), detail
        assert _codes(detail) == {TYPE_CODE}, detail


class TestНескінченнеУВкладеномуОбєкті:
    """stiffening_rib.height_mm = inf — регресія на побічний
    SHEET_EXCEEDS_MAX_LENGTH («inf мм»): `float("inf")` не кидає винятку,
    `validate/sheet.py` рахує `inf - (t+r)` і хибно відхиляє заготовку."""

    @pytest.mark.parametrize("bad", NONFINITE)
    def test_stiffening_rib_height_mm(self, client: TestClient, bad: str) -> None:
        res = _export(
            client,
            "enclosed_shelf",
            {**ENCLOSED_SHELF_VALID_PARAMS, "stiffening_rib": {"height_mm": bad}},
        )
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        assert "stiffening_rib.height_mm" in _fields_by_code(detail, TYPE_CODE), detail
        assert _codes(detail) == {TYPE_CODE}, (
            "SHEET_EXCEEDS_MAX_LENGTH чи інший побічний код — нейтралізоване "
            f"вкладене поле мало б дійти до sheet-гейта як None: {detail}"
        )

    @pytest.mark.parametrize("bad", NONFINITE)
    def test_side_perforation_pitch_x_mm(self, client: TestClient, bad: str) -> None:
        side_perforation = {
            "hole_size_mm": 10,
            "pitch_x_mm": bad,
            "pitch_y_mm": 20,
            "margin_mm": 20,
        }
        res = _export(
            client,
            "enclosed_shelf",
            {**ENCLOSED_SHELF_VALID_PARAMS, "side_perforation": side_perforation},
        )
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        assert "side_perforation.pitch_x_mm" in _fields_by_code(detail, TYPE_CODE), detail
        assert _codes(detail) == {TYPE_CODE}, detail


class TestHolesНеправильноїФорми:
    """`holes` не списком, елемент `holes` не об'єктом — 422, не мовчазний
    200 (holes.py й раніше ковтав такі значення без причини)."""

    @pytest.mark.parametrize(
        ("slug", "params"), [("l_bracket", VALID_PARAMS), ("z_bracket", Z_VALID_PARAMS)]
    )
    @pytest.mark.parametrize(
        "holes",
        ["not-a-list", 5, {"leg": "A"}],
        ids=["str", "int", "dict"],
    )
    def test_holes_не_список(
        self, client: TestClient, slug: str, params: dict[str, object], holes: object
    ) -> None:
        res = _export(client, slug, {**params, "holes": holes})
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        assert "holes" in _fields_by_code(detail, TYPE_CODE), detail
        assert _codes(detail) == {TYPE_CODE}, detail

    @pytest.mark.parametrize(
        ("holes", "bad_indices"),
        [
            (["invalid"], {0}),
            ([123], {0}),
            ([[1, 2]], {0}),
            ([GOOD_HOLE, "invalid"], {1}),
            (["invalid", GOOD_HOLE, 123], {0, 2}),
        ],
    )
    def test_holes_елемент_не_обєкт(
        self, client: TestClient, holes: list[object], bad_indices: set[int]
    ) -> None:
        res = _export(client, "l_bracket", {**VALID_PARAMS, "holes": holes})
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        fields = _fields_by_code(detail, TYPE_CODE)
        assert fields == {f"holes.{i}" for i in bad_indices}, detail
        assert _codes(detail) == {TYPE_CODE}, detail

    def test_holes_null_лишається_валідним(self, client: TestClient, aws_with_bucket: None) -> None:
        res = _export(client, "l_bracket", {**VALID_PARAMS, "holes": None})
        assert res.status_code == 200, res.text

    def test_holes_порожній_список_лишається_валідним(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        res = _export(client, "l_bracket", {**VALID_PARAMS, "holes": []})
        assert res.status_code == 200, res.text


class TestEnclosedОбєктНеправильноїФорми:
    """`side_perforation`/`stiffening_rib` не об'єктом — 422, `null` — як і
    раніше валідне «немає»."""

    @pytest.mark.parametrize("key", ["side_perforation", "stiffening_rib"])
    @pytest.mark.parametrize("bad", ["x", 5, [1, 2], True])
    def test_не_обєкт(self, client: TestClient, key: str, bad: object) -> None:
        res = _export(client, "enclosed_shelf", {**ENCLOSED_SHELF_VALID_PARAMS, key: bad})
        assert res.status_code == 422, res.text
        detail = res.json()["detail"]
        assert key in _fields_by_code(detail, TYPE_CODE), detail
        assert _codes(detail) == {TYPE_CODE}, detail

    @pytest.mark.parametrize("key", ["side_perforation", "stiffening_rib"])
    def test_null_лишається_валідним(
        self, client: TestClient, key: str, aws_with_bucket: None
    ) -> None:
        res = _export(client, "enclosed_shelf", {**ENCLOSED_SHELF_VALID_PARAMS, key: None})
        assert res.status_code == 200, res.text


class TestThicknessMm:
    """`thickness_mm` (корінь тіла, не `parameters`) — той самий дефект:
    `bool` коерсується у 1.0/0.0, NaN/Infinity валить 422-відповідь у 500."""

    @pytest.mark.parametrize("bad", [True, False])
    def test_bool_422_не_200(self, client: TestClient, bad: bool) -> None:
        res = _export(client, "l_bracket", VALID_PARAMS, t=bad)
        assert res.status_code == 422, res.text
        assert "thickness_mm" in res.text, res.text

    @pytest.mark.parametrize("lit", ["NaN", "Infinity", "-Infinity"])
    def test_json_літерал_422_не_500(self, client: TestClient, lit: str) -> None:
        body = (
            '{"template_slug":"l_bracket","thickness_mm":' + lit + ","
            '"material_code":"cold_rolled_steel","parameters":'
            '{"legA_mm":50,"legB_mm":40,"width_mm":30,'
            '"bend_radius_mm":2.5,"bend_angle_deg":90}}'
        )
        res = _raw(client, body)
        assert res.status_code == 422, res.text
        body_json = res.json()
        assert "thickness_mm" in str(body_json), body_json


class TestValidateTypesUnitНескінченне:
    """Юніт-тести самого гейта — isfinite, не лише parseable float()."""

    @pytest.mark.parametrize("bad", NONFINITE)
    def test_нескінченне_не_число(self, bad: str) -> None:
        errors = validate_export_types("l_bracket", {**VALID_PARAMS, "bend_radius_mm": bad})
        assert any(e["field"] == "bend_radius_mm" and e["code"] == TYPE_CODE for e in errors)

    def test_sanitize_нейтралізує_вкладене_поле(self) -> None:
        params = {
            **ENCLOSED_SHELF_VALID_PARAMS,
            "stiffening_rib": {"height_mm": "inf"},
        }
        errors = validate_export_types("enclosed_shelf", params)
        sanitized = sanitize_for_gates(params, errors)
        assert sanitized["stiffening_rib"]["height_mm"] is None
        assert params["stiffening_rib"] == {"height_mm": "inf"}  # оригінал не мутується
