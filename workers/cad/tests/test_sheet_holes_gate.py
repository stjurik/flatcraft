"""Тести sheet/holes/profile воркер-гейтів (CLAUDE.md §7 п.4, docs/07 §3) —
доробка draft PR #238 (#202) за рецензією Gemini 3.8 Flash, потім доробка
draft PR #241 (#202) за контрприкладами Claude Sonnet 5.5, потім доробка за
issue #246 (рішення yurii 2026-10-14 «1а», ADR-043): K-фактор гейту й
воркера — за матеріалом (`compute_k_factor`), не фіксований.

Регресії:
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
6. (issue #246, скасовує попередній пункт 6 цього файлу) Гейт габариту і
   воркер тепер ОБИДВА рахують K через `compute_k_factor(material_code, t, r)`
   — `TestSheetGateUsesComputeKFactorByMaterial` нижче. До цієї правки гейт і
   воркер навмисно ігнорували таблицю матеріалу й рахували фіксований K=0.4
   (PR #241) — рішення yurii 2026-10-14 «1а» це скасувало: K за матеріалом
   точніший для виробництва, а гейт має бачити ТОЙ САМИЙ габарит, що й
   реальна розгортка.
"""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

import boto3
import pytest
from fastapi.testclient import TestClient
from moto import mock_aws

from flatcraft_cad.k_factor import compute_k_factor
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
from flatcraft_cad.validate.sheet import (
    _sheet_dimensions_mm,
    validate_export_sheet,
)

SPEC = load_spec()
MATERIAL = "cold_rolled_steel"


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


@pytest.fixture(autouse=True)
def _s3_env(monkeypatch: pytest.MonkeyPatch) -> None:
    """Placeholder env — потрібен лише для happy-path кейсів нижче, що
    реально доходять до S3-upload (TestSheetGateUsesComputeKFactorByMaterial)."""
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
        k = compute_k_factor(MATERIAL, t, r, SPEC)
        u = unfold_l_bracket(params, k)
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
        k = compute_k_factor(MATERIAL, t, r, SPEC)
        u = unfold_corner_angle(params, k)
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
        k = compute_k_factor(MATERIAL, t, r, SPEC)
        u = unfold_z_bracket(params, k)
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
        k = compute_k_factor(MATERIAL, t, r, SPEC)
        u = unfold_wall_shelf(params, k)
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
        k = compute_k_factor(MATERIAL, t, r, SPEC)
        u = unfold_perforated_panel(params, k)
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
        k = compute_k_factor(MATERIAL, t, r, SPEC)
        u = unfold_enclosed_shelf(params, k)
        parameters: dict[str, Any] = {
            "width_mm": width,
            "depth_mm": depth,
            "bend_radius_mm": r,
            "bend_angle_deg": 90,
            "stiffening_rib": None if rib_height is None else {"height_mm": rib_height},
        }
        dims = _sheet_dimensions_mm("enclosed_shelf", parameters, t, MATERIAL)
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
            )
            is None
        )

    def test_sheet_dimensions_невідомий_материал_none(self) -> None:
        """`compute_k_factor` кидає ValueError на невідомому матеріалі —
        _sheet_dimensions_mm ловить його так само, як KeyError/TypeError
        (validate_export/validate_holes уже звітують реальну причину)."""
        assert (
            _sheet_dimensions_mm(
                "l_bracket",
                {
                    "legA_mm": 60,
                    "legB_mm": 60,
                    "bend_radius_mm": 2.5,
                    "bend_angle_deg": 90,
                    "width_mm": 100,
                },
                2.0,
                "unobtanium",
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


class TestSheetGateUsesComputeKFactorByMaterial:
    """Issue #246 (рішення yurii 2026-10-14 «1а», ADR-043).

    Регресія НАВПАКИ (скасовує попередню регресію з PR #241): гейт габариту і
    воркер мають рахувати ОДНАКОВИЙ K — тепер за матеріалом
    (`compute_k_factor`), а не фіксований 0.4. Контрольний кейс:

    z_bracket cold_rolled_steel t=8 R=5 top=bottom=400 offset=214 width=100:
    flat_sum = (400-8-5)+(214-8-5)+(400-8-5) = 975. ratio=R/t=5/8=0.625 → у
    діапазоні [0,1) → multiplier 0.85. BA(K) = (π/2)·(5+8·K).

    - cold_rolled_steel: K=0.40·0.85=0.34 → BA≈12.1265 → height≈999.2531мм
      (< 1000) → валідно.
    - aluminum_5754: K=0.33·0.85=0.2805 → height≈997.7577мм (< 1000) → валідно.
    - stainless_304: K=0.45·0.85=0.3825 → height≈1000.3212мм (> 1000) →
      SHEET_EXCEEDS_MAX_LENGTH.

    До цієї правки (PR #241) гейт і воркер ігнорували таблицю матеріалу й
    рахували фіксований K=0.4 (height≈1000.7566мм для всіх трьох — 422 для
    всіх незалежно від матеріалу). Тепер матеріал реально впливає на
    результат гейту, бо впливає на реальну розгортку воркера.
    """

    CONTREXAMPLE_PARAMETERS: dict[str, object] = {
        "top_flange_mm": 400,
        "bottom_flange_mm": 400,
        "offset_mm": 214,
        "bend_radius_mm": 5,
        "bend_angle_deg": 90,
        "width_mm": 100,
        "holes": [],
    }

    @pytest.mark.parametrize(
        ("material_code", "exceeds"),
        [
            ("cold_rolled_steel", False),
            ("aluminum_5754", False),
            ("stainless_304", True),
        ],
    )
    def test_z_bracket_t8_контрприклад_залежить_від_материалу(
        self, client: TestClient, aws_with_bucket: None, material_code: str, exceeds: bool
    ) -> None:
        # `aws_with_bucket` обов'язковий і для НЕ-exceeds кейсів: тепер вони
        # реально проходять гейт і йдуть у CAD-генерацію + S3-upload — без
        # мокнутого `mock_aws()` boto3 намагається реальний network call.
        res = client.post(
            "/export",
            json={
                "template_slug": "z_bracket",
                "parameters": self.CONTREXAMPLE_PARAMETERS,
                "thickness_mm": 8,
                "material_code": material_code,
            },
        )
        if exceeds:
            assert res.status_code == 422, res.text
            assert any(e["code"] == "SHEET_EXCEEDS_MAX_LENGTH" for e in res.json()["detail"])
        else:
            assert res.status_code == 200, res.text

    @pytest.mark.parametrize(
        "material_code",
        ["cold_rolled_steel", "aluminum_5754", "stainless_304"],
    )
    def test_validate_export_sheet_unit_level_залежить_від_материалу(
        self, material_code: str
    ) -> None:
        errors = validate_export_sheet(
            "z_bracket", self.CONTREXAMPLE_PARAMETERS, 8.0, material_code
        )
        exceeds = any(e["code"] == "SHEET_EXCEEDS_MAX_LENGTH" for e in errors)
        assert exceeds == (material_code == "stainless_304")

    @pytest.mark.parametrize(
        ("template_slug", "parameters", "t", "material_code", "unfold_fn", "build_params_cls"),
        [
            (
                "l_bracket",
                {
                    "legA_mm": 60.0,
                    "legB_mm": 60.0,
                    "width_mm": 100.0,
                    "bend_radius_mm": 5.0,
                    "bend_angle_deg": 90,
                },
                8.0,
                "cold_rolled_steel",
                unfold_l_bracket,
                LBracketBuildParameters,
            ),
            (
                "z_bracket",
                {
                    "top_flange_mm": 80.0,
                    "bottom_flange_mm": 80.0,
                    "offset_mm": 60.0,
                    "width_mm": 100.0,
                    "bend_radius_mm": 5.0,
                    "bend_angle_deg": 90,
                },
                8.0,
                "aluminum_5754",
                unfold_z_bracket,
                ZBracketBuildParameters,
            ),
        ],
    )
    def test_bbox_matches_real_unfold_built_with_compute_k_factor(
        self,
        template_slug: str,
        parameters: dict[str, Any],
        t: float,
        material_code: str,
        unfold_fn: Any,
        build_params_cls: Any,
    ) -> None:
        """Найсильніший тест: гейт рахує ТОЙ САМИЙ габарит, що й СПРАВЖНЯ
        розгортка воркера, побудована з `k_factor=compute_k_factor(material_code,
        t, r)` — тим самим шляхом, яким server.py будує розгортку."""
        r = float(parameters["bend_radius_mm"])
        k_factor = compute_k_factor(material_code, t, r, SPEC)
        params = build_params_cls.model_validate({**parameters, "thickness_mm": t})
        u = unfold_fn(params, k_factor)
        dims = _sheet_dimensions_mm(template_slug, parameters, t, material_code)
        assert dims is not None
        assert dims == pytest.approx((u.width_mm, u.length_mm), abs=1e-6)
