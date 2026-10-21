"""Тести issue #257: гейти воркера рахують параметри ПІСЛЯ Pydantic-дефолтів.

Регресія: прямий виклик `/export` (в обхід API, Zod уже не стоїть на шляху)
з НЕПОВНИМИ параметрами (без `bend_angle_deg`/`bend_radius_mm`) мовчки
проходив гейти (KeyError усередині `validate/*.py` → []), тоді як Pydantic у
`_generate_*` підставляв дефолт і будував деталь з параметрами, які з повним
payload гейт би відхилив. `_params_with_defaults` (`server.py`) вирішує
проблему раз, перед усіма п'ятьма `validate_export_*`.

Також (п.2) зіпсований отвір (без `diameter_mm`) більше не ковтає перевірку
решти отворів, і (п.3) `MATERIAL_NOT_ALLOWED` звітує лише `validate_export`
(bend), не дублюючись із sheet-гейту.
"""

from __future__ import annotations

import math

import pytest
from fastapi.testclient import TestClient

from flatcraft_cad.server import _params_with_defaults, app
from flatcraft_cad.validate.holes import validate_holes
from flatcraft_cad.validate.sheet import validate_export_sheet

from .test_server import PERFORATED_PANEL_VALID_PARAMS, VALID_PARAMS, WALL_SHELF_VALID_PARAMS


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


def _codes(response_json: dict[str, object]) -> set[str]:
    detail = response_json.get("detail")
    assert isinstance(detail, list)
    return {e["code"] for e in detail}


class TestWallShelfDefaultBendAngle:
    """1a: wall_shelf без `bend_angle_deg` (Pydantic-дефолт 90°) все одно
    відмовляє на SHEET_EXCEEDS_MAX_LENGTH — гейт бачить дефолтний кут."""

    PARAMS = {
        **WALL_SHELF_VALID_PARAMS,
        "width_mm": 3000,
        "bend_radius_mm": 5,
    }

    def test_контроль_з_явним_bend_angle_deg_422(self, client: TestClient) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "wall_shelf",
                "parameters": self.PARAMS,
                "thickness_mm": 8,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422, res.text
        assert "SHEET_EXCEEDS_MAX_LENGTH" in _codes(res.json())

    def test_без_bend_angle_deg_теж_422(self, client: TestClient) -> None:
        params = {k: v for k, v in self.PARAMS.items() if k != "bend_angle_deg"}
        res = client.post(
            "/export",
            json={
                "template_slug": "wall_shelf",
                "parameters": params,
                "thickness_mm": 8,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422, res.text
        assert "SHEET_EXCEEDS_MAX_LENGTH" in _codes(res.json())

    def test_без_кута_і_з_thickness_mm_у_parameters_рахує_req_thickness_mm(
        self, client: TestClient
    ) -> None:
        """thickness_mm усередині parameters (99) не перемагає req.thickness_mm (8)."""
        params = {k: v for k, v in self.PARAMS.items() if k != "bend_angle_deg"}
        res = client.post(
            "/export",
            json={
                "template_slug": "wall_shelf",
                "parameters": {**params, "thickness_mm": 99},
                "thickness_mm": 8,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422, res.text
        assert "SHEET_EXCEEDS_MAX_LENGTH" in _codes(res.json())


class TestPerforatedPanelDefaultRadius:
    """1b: perforated_panel без `bend_radius_mm`/`bend_angle_deg` — Pydantic-
    дефолт 2.5 не входить у allowed_inner_radius_mm для t=8 ([5.0]) →
    RADIUS_NOT_ALLOWED."""

    def test_без_bend_radius_mm_і_angle_422(self, client: TestClient) -> None:
        params = {
            k: v
            for k, v in PERFORATED_PANEL_VALID_PARAMS.items()
            if k not in ("bend_radius_mm", "bend_angle_deg")
        }
        res = client.post(
            "/export",
            json={
                "template_slug": "perforated_panel",
                "parameters": params,
                "thickness_mm": 8,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422, res.text
        assert "RADIUS_NOT_ALLOWED" in _codes(res.json())


class TestHoleOrderIndependentOfBrokenEntry:
    """2: зіпсований отвір (без diameter_mm) не скасовує перевірку решти —
    HOLE_TOO_CLOSE_TO_BEND спрацьовує незалежно від порядку в списку."""

    GOOD_BUT_TOO_CLOSE = {
        "leg": "A",
        "distance_from_edge_mm": 20,
        "distance_from_bend_mm": 5,
        "diameter_mm": 6,
    }
    BROKEN_NO_DIAMETER = {"leg": "A", "distance_from_edge_mm": 20, "distance_from_bend_mm": 30}

    def test_контроль_один_поганий_отвір_422(self, client: TestClient) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "l_bracket",
                "parameters": {**VALID_PARAMS, "holes": [self.GOOD_BUT_TOO_CLOSE]},
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422, res.text
        assert "HOLE_TOO_CLOSE_TO_BEND" in _codes(res.json())

    def test_поганий_потім_зіпсований_422(self, client: TestClient) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "l_bracket",
                "parameters": {
                    **VALID_PARAMS,
                    "holes": [self.GOOD_BUT_TOO_CLOSE, self.BROKEN_NO_DIAMETER],
                },
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422, res.text
        assert "HOLE_TOO_CLOSE_TO_BEND" in _codes(res.json())

    def test_зіпсований_потім_поганий_422(self, client: TestClient) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "l_bracket",
                "parameters": {
                    **VALID_PARAMS,
                    "holes": [self.BROKEN_NO_DIAMETER, self.GOOD_BUT_TOO_CLOSE],
                },
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422, res.text
        assert "HOLE_TOO_CLOSE_TO_BEND" in _codes(res.json())

    @pytest.mark.parametrize(
        "broken_hole",
        [
            {"leg": "A", "distance_from_edge_mm": 20, "distance_from_bend_mm": 30},  # без diameter
            {
                "leg": "A",
                "distance_from_edge_mm": 20,
                "distance_from_bend_mm": "not-a-number",
                "diameter_mm": 6,
            },
            {
                "leg": "A",
                "distance_from_edge_mm": 20,
                "distance_from_bend_mm": math.nan,
                "diameter_mm": 6,
            },
            {
                "leg": "A",
                "distance_from_edge_mm": 20,
                "distance_from_bend_mm": math.inf,
                "diameter_mm": 6,
            },
        ],
    )
    def test_validate_holes_unit_level_пропускає_лише_зіпсований(
        self, broken_hole: dict[str, object]
    ) -> None:
        errors = validate_holes(
            "l_bracket",
            {"bend_radius_mm": 2.5, "holes": [broken_hole, self.GOOD_BUT_TOO_CLOSE]},
            2.0,
            "cold_rolled_steel",
        )
        assert any(e.code == "HOLE_TOO_CLOSE_TO_BEND" for e in errors)


class TestMaterialNotAllowedReportedOnce:
    """3: z_bracket t=10 stainless_304 (поза групою для цієї товщини) дає
    РІВНО ОДИН MATERIAL_NOT_ALLOWED, а перевищення габариту НЕ губиться
    (контрприклади Gemini 4 Argon до #273: ранній return придушував
    SHEET_EXCEEDS_MAX_LENGTH). Розгортка 400+250+400 ≈ 1037.7 мм > 1000."""

    LONG = {
        "top_flange_mm": 400,
        "bottom_flange_mm": 400,
        "offset_mm": 250,
        "bend_radius_mm": 5,
        "bend_angle_deg": 90,
        "width_mm": 100,
    }

    def test_sheet_gate_не_додає_дубль_і_звітує_габарит(self) -> None:
        errors = validate_export_sheet("z_bracket", self.LONG, 10.0, "stainless_304")
        codes = [e["code"] for e in errors]
        assert "MATERIAL_NOT_ALLOWED" not in codes
        assert "SHEET_EXCEEDS_MAX_LENGTH" in codes

    def test_export_один_material_not_allowed_і_габарит(self, client: TestClient) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "z_bracket",
                "parameters": {**self.LONG, "holes": []},
                "thickness_mm": 10,
                "material_code": "stainless_304",
            },
        )
        assert res.status_code == 422, res.text
        codes = [e["code"] for e in res.json()["detail"]]
        assert codes.count("MATERIAL_NOT_ALLOWED") == 1
        assert "SHEET_EXCEEDS_MAX_LENGTH" in codes


class TestStringNumberInParameters:
    """Контрприклади Argon до #273: число рядком у parameters (Pydantic приводить)
    не має вимикати sheet-гейт."""

    def test_wall_shelf_back_height_рядком_422(self, client: TestClient) -> None:
        params = {
            **WALL_SHELF_VALID_PARAMS,
            "back_height_mm": "80",
            "width_mm": 3000,
            "bend_radius_mm": 5,
        }
        res = client.post(
            "/export",
            json={
                "template_slug": "wall_shelf",
                "parameters": params,
                "thickness_mm": 8,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422, res.text
        assert any(e["code"] == "SHEET_EXCEEDS_MAX_LENGTH" for e in res.json()["detail"])


class TestBrokenHoleAlone:
    """Зіпсований отвір сам по собі — пропускається, а не рахується як 0 мм."""

    @pytest.mark.parametrize(
        "hole",
        [
            {
                "leg": "A",
                "distance_from_edge_mm": 20,
                "distance_from_bend_mm": False,
                "diameter_mm": 6,
            },
            {
                "leg": "A",
                "distance_from_edge_mm": 20,
                "distance_from_bend_mm": 6.5,
                "diameter_mm": False,
            },
            {
                "leg": "A",
                "distance_from_edge_mm": 20,
                "distance_from_bend_mm": 30,
                "diameter_mm": math.nan,
            },
            {
                "leg": "A",
                "distance_from_edge_mm": 20,
                "distance_from_bend_mm": 30,
                "diameter_mm": math.inf,
            },
        ],
    )
    def test_пропускається(self, hole: dict[str, object]) -> None:
        errors = validate_holes(
            "l_bracket", {"bend_radius_mm": 2.5, "holes": [hole]}, 2.0, "cold_rolled_steel"
        )
        assert errors == []


class TestParamsWithDefaults:
    """Юніт-тести самої `_params_with_defaults` (server.py)."""

    def test_підставляє_дефолт_bend_angle_deg(self) -> None:
        result = _params_with_defaults(
            "wall_shelf",
            {k: v for k, v in WALL_SHELF_VALID_PARAMS.items() if k != "bend_angle_deg"},
            8.0,
        )
        assert result["bend_angle_deg"] == 90

    def test_req_thickness_mm_перемагає_поле_в_parameters(self) -> None:
        # Рецензія Flash до #273: без поля thickness_mm у parameters тест був порожнім.
        result = _params_with_defaults(
            "wall_shelf", {**WALL_SHELF_VALID_PARAMS, "thickness_mm": 99}, 8.0
        )
        assert result["thickness_mm"] == 8.0

    def test_поля_моделі_з_приведеними_типами_перемагають_сирі(self) -> None:
        # Контрприклади Argon до #273: рядок "80" з parameters повертався в гейт.
        result = _params_with_defaults(
            "wall_shelf", {**WALL_SHELF_VALID_PARAMS, "back_height_mm": "80"}, 2.0
        )
        assert result["back_height_mm"] == 80.0

    def test_зберігає_сирі_поля_яких_немає_в_моделі(self) -> None:
        result = _params_with_defaults("l_bracket", VALID_PARAMS, 2.0)
        assert result["holes"] == []

    def test_невалідні_parameters_повертає_як_є(self) -> None:
        broken = {**VALID_PARAMS, "legA_mm": "not-a-number"}
        assert _params_with_defaults("l_bracket", broken, 2.0) == broken
