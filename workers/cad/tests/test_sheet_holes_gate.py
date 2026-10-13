"""Тести sheet/holes/profile воркер-гейтів (CLAUDE.md §7 п.4, docs/07 §3) —
доробка draft PR #238 (#202) за рецензією Gemini 3.8 Flash.

П'ять регресій:
1. Габарит гейту `_sheet_dimensions_mm("enclosed_shelf", ...)` мав занижену Y
   (left/right звисають за bottom/back на (t+r)/2 навіть БЕЗ ребра — гейт
   рахував «низ» від 0). Найсильніший тест — ббокс гейту == бокс СПРАВЖНЬОГО
   полігона з `unfold.py` (з допуском 1e-6), для кожного шаблону.
2. Пряме читання `parameters[...]` у sheet.py/holes.py/profile.py мало
   KeyError на неповних параметрах → 500 замість 422.
3. `validate_export` (bend.py) не отримував `material_code` у server.py →
   MATERIAL_NOT_ALLOWED ніколи не спрацьовувало.
5. `material_code` — ОБОВ'ЯЗКОВИЙ (рішення Архітектора 2026-10-13): відсутній
   чи невідомий код мають давати 422, не мовчазний пропуск перевірки.
"""

from __future__ import annotations

from typing import Any

import pytest
from fastapi.testclient import TestClient

from flatcraft_cad.server import app
from flatcraft_cad.templates.corner_angle import CornerAngleBuildParameters
from flatcraft_cad.templates.enclosed_shelf import (
    EnclosedShelfBuildParameters,
    EnclosedShelfStiffeningRib,
)
from flatcraft_cad.templates.l_bracket import LBracketBuildParameters
from flatcraft_cad.templates.perforated_panel import PerforatedPanelBuildParameters
from flatcraft_cad.templates.wall_shelf import WallShelfBuildParameters
from flatcraft_cad.templates.z_bracket import ZBracketBuildParameters
from flatcraft_cad.unfold import (
    unfold_corner_angle,
    unfold_enclosed_shelf,
    unfold_l_bracket,
    unfold_perforated_panel,
    unfold_wall_shelf,
    unfold_z_bracket,
)
from flatcraft_cad.validate.bend import load_spec
from flatcraft_cad.validate.holes import validate_holes
from flatcraft_cad.validate.profile import validate_profile
from flatcraft_cad.validate.sheet import _compute_k_factor, _sheet_dimensions_mm

SPEC = load_spec()
MATERIAL = "cold_rolled_steel"


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


def _k(t: float, r: float) -> float:
    k = _compute_k_factor(MATERIAL, t, r, SPEC)
    assert k is not None, f"немає k-фактора для ({MATERIAL}, t={t}, r={r})"
    return k


class TestSheetDimensionsBboxParity:
    """Item 1: _sheet_dimensions_mm(...) == bbox СПРАВЖНЬОГО полігона unfold.py."""

    @pytest.mark.parametrize(
        ("leg_a", "leg_b", "width", "t", "r"),
        [
            (60.0, 60.0, 100.0, 2.0, 2.5),
            (40.0, 80.0, 200.0, 1.5, 2.5),
            (90.0, 30.0, 150.0, 3.0, 4.0),
        ],
    )
    def test_l_bracket(self, leg_a: float, leg_b: float, width: float, t: float, r: float) -> None:
        params = LBracketBuildParameters(
            legA_mm=leg_a,
            legB_mm=leg_b,
            bend_radius_mm=r,
            bend_angle_deg=90,
            width_mm=width,
            thickness_mm=t,
        )
        u = unfold_l_bracket(params, _k(t, r))
        dims = _sheet_dimensions_mm(
            "l_bracket",
            {
                "legA_mm": leg_a,
                "legB_mm": leg_b,
                "width_mm": width,
                "bend_radius_mm": r,
                "bend_angle_deg": 90,
            },
            t,
            MATERIAL,
            SPEC,
        )
        assert dims is not None
        assert dims == pytest.approx((u.width_mm, u.length_mm), abs=1e-6)

    @pytest.mark.parametrize(
        ("leg_a", "leg_b", "width", "t", "r"),
        [(50.0, 50.0, 80.0, 2.0, 2.5), (70.0, 40.0, 120.0, 2.5, 4.0)],
    )
    def test_corner_angle(
        self, leg_a: float, leg_b: float, width: float, t: float, r: float
    ) -> None:
        params = CornerAngleBuildParameters(
            legA_mm=leg_a,
            legB_mm=leg_b,
            bend_radius_mm=r,
            bend_angle_deg=90,
            width_mm=width,
            thickness_mm=t,
            hole_diameter_mm=5.0,
            hole_rows=1,
            hole_cols=2,
            hole_margin_mm=10.0,
        )
        u = unfold_corner_angle(params, _k(t, r))
        dims = _sheet_dimensions_mm(
            "corner_angle",
            {
                "legA_mm": leg_a,
                "legB_mm": leg_b,
                "width_mm": width,
                "bend_radius_mm": r,
                "bend_angle_deg": 90,
            },
            t,
            MATERIAL,
            SPEC,
        )
        assert dims is not None
        assert dims == pytest.approx((u.width_mm, u.length_mm), abs=1e-6)

    @pytest.mark.parametrize(
        ("top", "bottom", "offset", "width", "t", "r"),
        [
            (60.0, 60.0, 40.0, 100.0, 2.0, 2.5),
            (80.0, 40.0, 60.0, 150.0, 1.5, 2.5),
        ],
    )
    def test_z_bracket(
        self, top: float, bottom: float, offset: float, width: float, t: float, r: float
    ) -> None:
        params = ZBracketBuildParameters(
            top_flange_mm=top,
            bottom_flange_mm=bottom,
            offset_mm=offset,
            bend_radius_mm=r,
            bend_angle_deg=90,
            width_mm=width,
            thickness_mm=t,
        )
        u = unfold_z_bracket(params, _k(t, r))
        dims = _sheet_dimensions_mm(
            "z_bracket",
            {
                "top_flange_mm": top,
                "bottom_flange_mm": bottom,
                "offset_mm": offset,
                "width_mm": width,
                "bend_radius_mm": r,
                "bend_angle_deg": 90,
            },
            t,
            MATERIAL,
            SPEC,
        )
        assert dims is not None
        assert dims == pytest.approx((u.width_mm, u.length_mm), abs=1e-6)

    @pytest.mark.parametrize(
        ("back", "shelf", "lip", "width", "t", "r"),
        [
            (80.0, 150.0, 20.0, 300.0, 2.0, 2.5),  # з lip
            (80.0, 150.0, 0.0, 300.0, 2.0, 2.5),  # без lip
        ],
    )
    def test_wall_shelf(
        self, back: float, shelf: float, lip: float, width: float, t: float, r: float
    ) -> None:
        params = WallShelfBuildParameters(
            back_height_mm=back,
            shelf_depth_mm=shelf,
            front_lip_mm=lip,
            bend_radius_mm=r,
            bend_angle_deg=90,
            width_mm=width,
            thickness_mm=t,
            mount_hole_diameter_mm=6.0,
            mount_hole_rows=2,
            mount_hole_cols=2,
            mount_hole_margin_mm=15.0,
        )
        u = unfold_wall_shelf(params, _k(t, r))
        dims = _sheet_dimensions_mm(
            "wall_shelf",
            {
                "back_height_mm": back,
                "shelf_depth_mm": shelf,
                "front_lip_mm": lip,
                "width_mm": width,
                "bend_radius_mm": r,
                "bend_angle_deg": 90,
            },
            t,
            MATERIAL,
            SPEC,
        )
        assert dims is not None
        assert dims == pytest.approx((u.width_mm, u.length_mm), abs=1e-6)

    @pytest.mark.parametrize(
        ("length", "width", "rib_height", "t", "r"),
        [(200.0, 150.0, 30.0, 2.0, 2.5), (400.0, 300.0, 40.0, 1.5, 4.0)],
    )
    def test_perforated_panel(
        self, length: float, width: float, rib_height: float, t: float, r: float
    ) -> None:
        params = PerforatedPanelBuildParameters.model_validate(
            {
                "length_mm": length,
                "width_mm": width,
                "thickness_mm": t,
                "hole_shape": "square",
                "hole_size_mm": 8.0,
                "pitch_x_mm": 20.0,
                "pitch_y_mm": 20.0,
                "margin_mm": 15.0,
                "rib_height_mm": rib_height,
                "bend_radius_mm": r,
            }
        )
        u = unfold_perforated_panel(params, _k(t, r))
        dims = _sheet_dimensions_mm(
            "perforated_panel",
            {
                "length_mm": length,
                "width_mm": width,
                "rib_height_mm": rib_height,
                "bend_radius_mm": r,
                "bend_angle_deg": 90,
            },
            t,
            MATERIAL,
            SPEC,
        )
        assert dims is not None
        expected = (
            u.bbox_max_x_mm - u.bbox_min_x_mm,
            u.bbox_max_y_mm - u.bbox_min_y_mm,
        )
        assert dims == pytest.approx(expected, abs=1e-6)

    @pytest.mark.parametrize(
        ("width", "depth", "t", "r", "rib_height"),
        [
            (600.0, 200.0, 2.0, 2.5, None),  # без ребра — регресія #1
            (600.0, 200.0, 1.5, 2.5, None),
            (500.0, 150.0, 3.0, 4.0, None),
            (600.0, 200.0, 2.0, 2.5, 15.0),  # з ребром
            (500.0, 150.0, 3.0, 4.0, 10.0),
        ],
    )
    def test_enclosed_shelf(
        self, width: float, depth: float, t: float, r: float, rib_height: float | None
    ) -> None:
        stiffening_rib = (
            None if rib_height is None else EnclosedShelfStiffeningRib(height_mm=rib_height)
        )
        params = EnclosedShelfBuildParameters(
            width_mm=width,
            depth_mm=depth,
            bend_radius_mm=r,
            bend_angle_deg=90,
            thickness_mm=t,
            stiffening_rib=stiffening_rib,
        )
        u = unfold_enclosed_shelf(params, _k(t, r))
        parameters: dict[str, Any] = {
            "width_mm": width,
            "depth_mm": depth,
            "bend_radius_mm": r,
            "bend_angle_deg": 90,
            "stiffening_rib": None if rib_height is None else {"height_mm": rib_height},
        }
        dims = _sheet_dimensions_mm("enclosed_shelf", parameters, t, MATERIAL, SPEC)
        assert dims is not None
        expected = (
            u.bbox_max_x_mm - u.bbox_min_x_mm,
            u.bbox_max_y_mm - u.bbox_min_y_mm,
        )
        assert dims == pytest.approx(expected, abs=1e-6)


class TestIncompleteParametersGiveSchema422NotCrash:
    """Item 2: пряме читання `parameters[...]` — під try/except, не 500."""

    def test_l_bracket_без_lega_mm_422_не_500(self, client: TestClient) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "l_bracket",
                "parameters": {
                    "legB_mm": 60,
                    "bend_radius_mm": 2.5,
                    "bend_angle_deg": 90,
                    "width_mm": 100,
                    "holes": [],
                },
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422, res.text

    def test_validate_profile_без_lega_mm_повертає_порожньо(self) -> None:
        assert (
            validate_profile(
                "l_bracket",
                {"legB_mm": 60, "bend_radius_mm": 2.5, "width_mm": 100},
                2.0,
            )
            == []
        )

    def test_validate_holes_без_bend_radius_mm_повертає_порожньо(self) -> None:
        assert (
            validate_holes(
                "l_bracket",
                {
                    "holes": [
                        {"leg": "A", "distance_from_bend_mm": 9.5, "diameter_mm": 6},
                    ],
                },
                2.0,
                MATERIAL,
                SPEC,
            )
            == []
        )

    def test_sheet_dimensions_без_lega_mm_none(self) -> None:
        assert (
            _sheet_dimensions_mm(
                "l_bracket",
                {"legB_mm": 60, "bend_radius_mm": 2.5, "bend_angle_deg": 90, "width_mm": 100},
                2.0,
                MATERIAL,
                SPEC,
            )
            is None
        )


class TestMaterialCodeWiredIntoBendValidation:
    """Item 3: validate_export(bend) отримує material_code → MATERIAL_NOT_ALLOWED
    спрацьовує, коли матеріал не входить у групу для цієї товщини."""

    def test_stainless_304_t10_не_входить_у_групу_422(self, client: TestClient) -> None:
        # t=10.0 → group "carbon_alu_galv_only" (без stainless_304/430).
        res = client.post(
            "/export",
            json={
                "template_slug": "z_bracket",
                "parameters": {
                    "top_flange_mm": 60,
                    "bottom_flange_mm": 60,
                    "offset_mm": 40,
                    "bend_radius_mm": 5,
                    "bend_angle_deg": 90,
                    "width_mm": 100,
                    "holes": [],
                },
                "thickness_mm": 10,
                "material_code": "stainless_304",
            },
        )
        assert res.status_code == 422, res.text
        assert any(e["code"] == "MATERIAL_NOT_ALLOWED" for e in res.json()["detail"])


class TestMaterialCodeMandatory:
    """Item 5: material_code ОБОВ'ЯЗКОВИЙ (рішення Архітектора 2026-10-13)."""

    VALID_L_BRACKET_PARAMS: dict[str, object] = {
        "legA_mm": 60,
        "legB_mm": 60,
        "bend_radius_mm": 2.5,
        "bend_angle_deg": 90,
        "width_mm": 100,
        "holes": [],
    }

    def test_export_без_material_code_422(self, client: TestClient) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "l_bracket",
                "parameters": self.VALID_L_BRACKET_PARAMS,
                "thickness_mm": 2,
            },
        )
        assert res.status_code == 422, res.text

    def test_export_невідомий_material_code_422(self, client: TestClient) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "l_bracket",
                "parameters": self.VALID_L_BRACKET_PARAMS,
                "thickness_mm": 2,
                "material_code": "unobtanium",
            },
        )
        assert res.status_code == 422, res.text
        assert any(e["code"] == "MATERIAL_NOT_ALLOWED" for e in res.json()["detail"])

    def test_validate_holes_невідомий_material_code_помилка(self) -> None:
        errors = validate_holes(
            "l_bracket",
            {
                "bend_radius_mm": 2.5,
                "holes": [
                    {"leg": "A", "distance_from_bend_mm": 9.5, "diameter_mm": 6},
                ],
            },
            2.0,
            "unobtanium",
            SPEC,
        )
        assert any(e.code == "HOLE_MATERIAL_COEFFICIENT_MISSING" for e in errors)

    def test_validate_holes_material_code_none_помилка(self) -> None:
        errors = validate_holes(
            "l_bracket",
            {
                "bend_radius_mm": 2.5,
                "holes": [
                    {"leg": "A", "distance_from_bend_mm": 9.5, "diameter_mm": 6},
                ],
            },
            2.0,
            None,
            SPEC,
        )
        assert any(e.code == "HOLE_MATERIAL_COEFFICIENT_MISSING" for e in errors)
