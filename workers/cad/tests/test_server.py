"""Тести FastAPI /export — Pydantic-валідація + flow з mock'ed S3."""

from __future__ import annotations

import os
from collections.abc import Iterator
from tempfile import NamedTemporaryFile

import boto3
import pytest
from fastapi.testclient import TestClient
from moto import mock_aws

from flatcraft_cad.server import app


@pytest.fixture(autouse=True)
def _s3_env(monkeypatch: pytest.MonkeyPatch) -> None:
    """moto перехоплює boto3 виклики; ENV-и потрібні лише як placeholder."""
    # S3_ENDPOINT не виставляємо — server fallback на None дає AWS-resolver,
    # який перехоплює moto. У dev/prod значення береться з .env (MinIO/R2).
    monkeypatch.delenv("S3_ENDPOINT", raising=False)
    monkeypatch.setenv("S3_ACCESS_KEY_ID", "test")
    monkeypatch.setenv("S3_SECRET_ACCESS_KEY", "test")
    monkeypatch.setenv("S3_BUCKET", "flatcraft-test")
    monkeypatch.setenv("S3_REGION", "us-east-1")


@pytest.fixture
def aws_with_bucket() -> Iterator[None]:
    """moto перехоплює всі boto3 виклики у scope. Створюємо bucket для тестів."""
    with mock_aws():
        s3 = boto3.client("s3", region_name="us-east-1")
        s3.create_bucket(Bucket="flatcraft-test")
        yield


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


VALID_PARAMS: dict[str, object] = {
    "legA_mm": 60,
    "legB_mm": 60,
    "bend_radius_mm": 2.5,
    "bend_angle_deg": 90,
    "width_mm": 100,
    "holes": [],
}

Z_VALID_PARAMS: dict[str, object] = {
    "top_flange_mm": 60,
    "bottom_flange_mm": 60,
    "offset_mm": 40,
    "bend_radius_mm": 2.5,
    "bend_angle_deg": 90,
    "width_mm": 100,
    "holes": [],
}


class TestHealth:
    def test_health_повертає_ok(self, client: TestClient) -> None:
        res = client.get("/health")
        assert res.status_code == 200
        assert res.json() == {"status": "ok"}


CORNER_VALID_PARAMS: dict[str, object] = {
    "legA_mm": 50,
    "legB_mm": 50,
    "bend_radius_mm": 2.5,
    "bend_angle_deg": 90,
    "width_mm": 80,
    "hole_diameter_mm": 5,
    "hole_rows": 1,
    "hole_cols": 2,
    "hole_margin_mm": 12,
}


WALL_SHELF_VALID_PARAMS: dict[str, object] = {
    "back_height_mm": 80,
    "shelf_depth_mm": 150,
    "front_lip_mm": 20,
    "bend_radius_mm": 2.5,
    "bend_angle_deg": 90,
    "width_mm": 300,
    "mount_hole_diameter_mm": 6,
    "mount_hole_rows": 2,
    "mount_hole_cols": 2,
    "mount_hole_margin_mm": 15,
}


PERFORATED_PANEL_VALID_PARAMS: dict[str, object] = {
    "length_mm": 200,
    "width_mm": 150,
    "hole_shape": "square",
    "hole_size_mm": 8,
    "pitch_x_mm": 20,
    "pitch_y_mm": 20,
    "margin_mm": 15,
    "rib_height_mm": 30,
    "bend_radius_mm": 2.5,
    "bend_angle_deg": 90,
}

ENCLOSED_SHELF_VALID_PARAMS: dict[str, object] = {
    "width_mm": 600,
    "depth_mm": 200,
    "bend_radius_mm": 2.5,
    "bend_angle_deg": 90,
    "bends": [
        {"direction": "up"},
        {"direction": "up"},
        {"direction": "up"},
        {"direction": "up"},
    ],
    "side_perforation": None,
    "stiffening_rib": None,
}


class TestExportValidation:
    def test_невалідний_template_slug_422(self, client: TestClient) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "non_existent_template",
                "parameters": VALID_PARAMS,
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422
        assert res.json()["detail"][0]["type"] == "literal_error", res.text

    def test_leg_a_за_межами_422(self, client: TestClient) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "l_bracket",
                "parameters": {**VALID_PARAMS, "legA_mm": 10},
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422
        assert res.json()["detail"].startswith("invalid_parameters"), res.text
        assert "\nlegA_mm\n" in res.json()["detail"], res.text

    def test_невідоме_поле_у_request_422(self, client: TestClient) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "l_bracket",
                "parameters": VALID_PARAMS,
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
                "extra_garbage": "x",
            },
        )
        assert res.status_code == 422
        assert res.json()["detail"][0]["type"] == "extra_forbidden", res.text


class TestExportHappy:
    def test_успішний_експорт_заливає_dxf_і_pdf_артефакти(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "l_bracket",
                "parameters": VALID_PARAMS,
                "thickness_mm": 2,
                "k_factor": 0.4,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 200, res.text
        body = res.json()
        assert "artifacts" in body
        assert set(body["artifacts"].keys()) == {"dxf", "pdf"}

        s3 = boto3.client("s3", region_name="us-east-1")

        for kind, content_type in [("dxf", "application/dxf"), ("pdf", "application/pdf")]:
            art = body["artifacts"][kind]
            assert art["bytes"] > 0
            assert art["s3_key"].startswith("exports/")
            assert art["s3_key"].endswith(f"_l_bracket.{kind}")
            # SigV2 (Signature=) або SigV4 (X-Amz-Signature) — обидва ОК.
            assert "Signature=" in art["url"] or "X-Amz-Signature" in art["url"]
            head = s3.head_object(Bucket=os.environ["S3_BUCKET"], Key=art["s3_key"])
            assert head["ContentLength"] == art["bytes"]
            assert head["ContentType"] == content_type

    def test_dxf_і_pdf_мають_спільний_timestamp_у_s3_key(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        """Один HTTP-виклик → один timestamp prefix для обох артефактів,
        щоб у бакеті dxf і pdf лежали поруч одного export'у."""
        res = client.post(
            "/export",
            json={
                "template_slug": "l_bracket",
                "parameters": VALID_PARAMS,
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        body = res.json()
        dxf_prefix = body["artifacts"]["dxf"]["s3_key"].rsplit(".", 1)[0]
        pdf_prefix = body["artifacts"]["pdf"]["s3_key"].rsplit(".", 1)[0]
        assert dxf_prefix == pdf_prefix

    def test_детермінізм_однакові_params_однакові_байти(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        payload = {
            "template_slug": "l_bracket",
            "parameters": VALID_PARAMS,
            "thickness_mm": 2,
            "k_factor": 0.4,
            "material_code": "cold_rolled_steel",
        }
        a = client.post("/export", json=payload).json()
        b = client.post("/export", json=payload).json()
        assert a["artifacts"]["dxf"]["bytes"] == b["artifacts"]["dxf"]["bytes"]
        assert a["artifacts"]["pdf"]["bytes"] == b["artifacts"]["pdf"]["bytes"]
        s3 = boto3.client("s3", region_name="us-east-1")
        for kind in ("dxf", "pdf"):
            body_a = s3.get_object(
                Bucket=os.environ["S3_BUCKET"], Key=a["artifacts"][kind]["s3_key"]
            )["Body"].read()
            body_b = s3.get_object(
                Bucket=os.environ["S3_BUCKET"], Key=b["artifacts"][kind]["s3_key"]
            )["Body"].read()
            assert body_a == body_b, f"{kind} not deterministic"


class TestZBracketExport:
    def test_z_bracket_успішний_експорт_dxf_і_pdf(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "z_bracket",
                "parameters": Z_VALID_PARAMS,
                "thickness_mm": 2,
                "k_factor": 0.4,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 200, res.text
        body = res.json()
        assert "artifacts" in body
        for kind in ("dxf", "pdf"):
            art = body["artifacts"][kind]
            assert art["bytes"] > 0
            assert art["s3_key"].endswith(f"_z_bracket.{kind}")

    def test_z_bracket_offset_за_межами_422(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "z_bracket",
                "parameters": {**Z_VALID_PARAMS, "offset_mm": 10},
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422
        assert res.json()["detail"].startswith("invalid_parameters"), res.text
        assert "\noffset_mm\n" in res.json()["detail"], res.text

    def test_l_і_z_bracket_дають_різні_артефакти(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        l_res = client.post(
            "/export",
            json={
                "template_slug": "l_bracket",
                "parameters": VALID_PARAMS,
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        ).json()
        z_res = client.post(
            "/export",
            json={
                "template_slug": "z_bracket",
                "parameters": Z_VALID_PARAMS,
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        ).json()
        s3 = boto3.client("s3", region_name="us-east-1")
        l_dxf = s3.get_object(
            Bucket=os.environ["S3_BUCKET"], Key=l_res["artifacts"]["dxf"]["s3_key"]
        )["Body"].read()
        z_dxf = s3.get_object(
            Bucket=os.environ["S3_BUCKET"], Key=z_res["artifacts"]["dxf"]["s3_key"]
        )["Body"].read()
        assert l_dxf != z_dxf


class TestCornerAngleExport:
    def test_corner_angle_успішний_експорт_dxf_і_pdf(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "corner_angle",
                "parameters": CORNER_VALID_PARAMS,
                "thickness_mm": 2,
                "k_factor": 0.4,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 200, res.text
        body = res.json()
        for kind in ("dxf", "pdf"):
            art = body["artifacts"][kind]
            assert art["bytes"] > 0
            assert art["s3_key"].endswith(f"_corner_angle.{kind}")

    def test_corner_angle_hole_rows_за_межами_422(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "corner_angle",
                "parameters": {**CORNER_VALID_PARAMS, "hole_rows": 6},
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422
        assert res.json()["detail"].startswith("invalid_parameters"), res.text
        assert "\nhole_rows\n" in res.json()["detail"], res.text

    def test_corner_angle_dxf_має_inner_cuts_layer(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        """1×2 grid × 2 полиці = 4 отвори → DXF має CIRCLE entities на LASER_CUT (ADR-024)."""
        res = client.post(
            "/export",
            json={
                "template_slug": "corner_angle",
                "parameters": CORNER_VALID_PARAMS,
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        ).json()
        s3 = boto3.client("s3", region_name="us-east-1")
        dxf_bytes = s3.get_object(
            Bucket=os.environ["S3_BUCKET"], Key=res["artifacts"]["dxf"]["s3_key"]
        )["Body"].read()
        dxf_text = dxf_bytes.decode("utf-8")
        # 4 CIRCLE entities, всі на LASER_CUT (ADR-024: 2 шари, отвори color 5).
        assert dxf_text.count("\nCIRCLE\n") == 4
        assert "LASER_CUT" in dxf_text
        assert "INNER_CUTS" not in dxf_text

    def test_l_і_corner_angle_дають_різні_артефакти(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        """corner_angle і L-bracket з однаковими розмірами полиць мають
        різні DXF через grid отворів у corner_angle."""
        l_res = client.post(
            "/export",
            json={
                "template_slug": "l_bracket",
                "parameters": {**VALID_PARAMS, "legA_mm": 50, "legB_mm": 50, "width_mm": 80},
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        ).json()
        c_res = client.post(
            "/export",
            json={
                "template_slug": "corner_angle",
                "parameters": CORNER_VALID_PARAMS,
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        ).json()
        s3 = boto3.client("s3", region_name="us-east-1")
        l_dxf = s3.get_object(
            Bucket=os.environ["S3_BUCKET"], Key=l_res["artifacts"]["dxf"]["s3_key"]
        )["Body"].read()
        c_dxf = s3.get_object(
            Bucket=os.environ["S3_BUCKET"], Key=c_res["artifacts"]["dxf"]["s3_key"]
        )["Body"].read()
        assert l_dxf != c_dxf


class TestWallShelfExport:
    def test_wall_shelf_успішний_експорт_dxf_і_pdf(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "wall_shelf",
                "parameters": WALL_SHELF_VALID_PARAMS,
                "thickness_mm": 2,
                "k_factor": 0.4,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 200, res.text
        body = res.json()
        for kind in ("dxf", "pdf"):
            art = body["artifacts"][kind]
            assert art["bytes"] > 0
            assert art["s3_key"].endswith(f"_wall_shelf.{kind}")

    def test_wall_shelf_back_за_межами_422(self, client: TestClient, aws_with_bucket: None) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "wall_shelf",
                "parameters": {**WALL_SHELF_VALID_PARAMS, "back_height_mm": 10},
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422
        assert res.json()["detail"].startswith("invalid_parameters"), res.text
        assert "\nback_height_mm\n" in res.json()["detail"], res.text

    def test_wall_shelf_без_lip_має_1_bend(self, client: TestClient, aws_with_bucket: None) -> None:
        """front_lip=0 → DXF має лише 1 лінію гибу (не 2). ADR-024: рахуємо
        LINE-entities на BEND_LINES, бо текстових BEND-анотацій у DXF немає."""
        # З lip: 2 bend lines.
        with_lip_res = client.post(
            "/export",
            json={
                "template_slug": "wall_shelf",
                "parameters": WALL_SHELF_VALID_PARAMS,
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        ).json()
        # Без lip: 1 bend line.
        without_lip_res = client.post(
            "/export",
            json={
                "template_slug": "wall_shelf",
                "parameters": {**WALL_SHELF_VALID_PARAMS, "front_lip_mm": 0},
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        ).json()
        s3 = boto3.client("s3", region_name="us-east-1")
        with_lip = (
            s3.get_object(
                Bucket=os.environ["S3_BUCKET"],
                Key=with_lip_res["artifacts"]["dxf"]["s3_key"],
            )["Body"]
            .read()
            .decode("utf-8")
        )
        without_lip = (
            s3.get_object(
                Bucket=os.environ["S3_BUCKET"],
                Key=without_lip_res["artifacts"]["dxf"]["s3_key"],
            )["Body"]
            .read()
            .decode("utf-8")
        )
        # Лінії гибу = LINE-entities (outer — LWPOLYLINE, отвори — CIRCLE).
        assert with_lip.count("\nLINE\n") == 2
        assert without_lip.count("\nLINE\n") == 1

    def test_wall_shelf_dxf_має_4_inner_cuts_circles(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        """2×2 mount holes = 4 CIRCLE entities на LASER_CUT (ADR-024)."""
        res = client.post(
            "/export",
            json={
                "template_slug": "wall_shelf",
                "parameters": WALL_SHELF_VALID_PARAMS,
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        ).json()
        s3 = boto3.client("s3", region_name="us-east-1")
        dxf = (
            s3.get_object(Bucket=os.environ["S3_BUCKET"], Key=res["artifacts"]["dxf"]["s3_key"])[
                "Body"
            ]
            .read()
            .decode("utf-8")
        )
        assert dxf.count("\nCIRCLE\n") == 4
        assert "LASER_CUT" in dxf
        assert "INNER_CUTS" not in dxf


class TestPerforatedPanelExport:
    def test_perforated_panel_успішний_експорт_dxf_і_pdf(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "perforated_panel",
                "parameters": PERFORATED_PANEL_VALID_PARAMS,
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 200, res.text
        body = res.json()
        for kind in ("dxf", "pdf"):
            art = body["artifacts"][kind]
            assert art["bytes"] > 0
            assert art["s3_key"].endswith(f"_perforated_panel.{kind}")

    def test_perforated_panel_pitch_x_за_межами_422(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "perforated_panel",
                "parameters": {**PERFORATED_PANEL_VALID_PARAMS, "pitch_x_mm": 5},
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422
        # Відмовляє гейт перфорації (validate_export_perforation), а не схема.
        assert {(e["code"], e["field"]) for e in res.json()["detail"]} == {
            ("HOLES_OVERLAP", "pitch_x_mm")
        }, res.text

    def test_perforated_panel_dxf_layers_and_holes(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        """Ребриста панель (ADR-031): square-перфо → LWPOLYLINE; 4 кутові Ø5.5 →
        CIRCLE; є BEND_LINES (4 ребра); ADR-024: жодного TEXT у DXF."""
        res = client.post(
            "/export",
            json={
                "template_slug": "perforated_panel",
                "parameters": PERFORATED_PANEL_VALID_PARAMS,
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        ).json()
        s3 = boto3.client("s3", region_name="us-east-1")
        dxf = (
            s3.get_object(Bucket=os.environ["S3_BUCKET"], Key=res["artifacts"]["dxf"]["s3_key"])[
                "Body"
            ]
            .read()
            .decode("utf-8")
        )
        # ADR-024: у DXF немає TEXT/BEND-анотацій.
        assert dxf.count("BEND ") == 0
        assert "\nTEXT\n" not in dxf
        # Квадратна перфо → LWPOLYLINE; рівно 4 CIRCLE — кутові установочні отвори.
        assert dxf.count("\nCIRCLE\n") == 4
        # Лоток має 4 лінії гибу.
        assert "BEND_LINES" in dxf
        assert "LASER_CUT" in dxf
        assert "INNER_CUTS" not in dxf

    def test_perforated_panel_pitch_впливає_на_кількість_отворів(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        """Більший pitch → менше отворів у DXF (square-перфо → LWPOLYLINE)."""
        small_pitch = client.post(
            "/export",
            json={
                "template_slug": "perforated_panel",
                "parameters": PERFORATED_PANEL_VALID_PARAMS,
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        ).json()
        big_pitch = client.post(
            "/export",
            json={
                "template_slug": "perforated_panel",
                "parameters": {
                    **PERFORATED_PANEL_VALID_PARAMS,
                    "pitch_x_mm": 50,
                    "pitch_y_mm": 50,
                },
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        ).json()
        s3 = boto3.client("s3", region_name="us-east-1")
        small = (
            s3.get_object(
                Bucket=os.environ["S3_BUCKET"], Key=small_pitch["artifacts"]["dxf"]["s3_key"]
            )["Body"]
            .read()
            .decode("utf-8")
        )
        big = (
            s3.get_object(
                Bucket=os.environ["S3_BUCKET"], Key=big_pitch["artifacts"]["dxf"]["s3_key"]
            )["Body"]
            .read()
            .decode("utf-8")
        )
        assert small.count("\nLWPOLYLINE\n") > big.count("\nLWPOLYLINE\n")


class TestEnclosedShelfExport:
    """Issue #237 п.1 (рішення yurii 2026-10-14 «3а»): лише 'up'."""

    def test_enclosed_shelf_успішний_експорт_dxf_і_pdf(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "enclosed_shelf",
                "parameters": ENCLOSED_SHELF_VALID_PARAMS,
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 200, res.text
        body = res.json()
        for kind in ("dxf", "pdf"):
            art = body["artifacts"][kind]
            assert art["bytes"] > 0
            assert art["s3_key"].endswith(f"_enclosed_shelf.{kind}")

    def test_enclosed_shelf_down_422(self, client: TestClient, aws_with_bucket: None) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "enclosed_shelf",
                "parameters": {
                    **ENCLOSED_SHELF_VALID_PARAMS,
                    "bends": [
                        {"direction": "up"},
                        {"direction": "down"},
                        {"direction": "up"},
                        {"direction": "up"},
                    ],
                },
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422
        # Саме через напрям: шлях `bends.1.direction` дає лише Pydantic-валідатор шаблону
        # (у вхідному JSON, який FastAPI повторює в 422, такого рядка немає).
        assert "bends.1.direction" in res.json()["detail"], res.text


class TestExportIdPermalink:
    """Issue #70: export_id → QR-permalink {BASE_URL}/f/{export_id} у PDF."""

    def test_export_id_плюс_base_url_дає_permalink_у_pdf(
        self, client: TestClient, aws_with_bucket: None, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setenv("BASE_URL", "https://hart.crimea.ua")
        export_id = "00000000-1111-2222-3333-444444444444"
        res = client.post(
            "/export",
            json={
                "template_slug": "l_bracket",
                "parameters": VALID_PARAMS,
                "thickness_mm": 2,
                "export_id": export_id,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 200, res.text
        pdf_key = res.json()["artifacts"]["pdf"]["s3_key"]
        s3 = boto3.client("s3", region_name="us-east-1")
        pdf_bytes = s3.get_object(Bucket=os.environ["S3_BUCKET"], Key=pdf_key)["Body"].read()

        from pypdf import PdfReader

        with NamedTemporaryFile(suffix=".pdf") as f:
            f.write(pdf_bytes)
            f.flush()
            text = PdfReader(f.name).pages[0].extract_text() or ""
        # QR-текстова мітка обрізана до 48 символів (_draw_qr) — перевіряємо
        # префікс permalink, повний export_id закодований лише у самому QR-зображенні.
        assert "QR: https://hart.crimea.ua/f/" in text
        assert "flatcraft://" not in text

    def test_без_export_id_лишається_fallback_scheme(
        self, client: TestClient, aws_with_bucket: None, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setenv("BASE_URL", "https://hart.crimea.ua")
        res = client.post(
            "/export",
            json={
                "template_slug": "l_bracket",
                "parameters": VALID_PARAMS,
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 200, res.text
        pdf_key = res.json()["artifacts"]["pdf"]["s3_key"]
        s3 = boto3.client("s3", region_name="us-east-1")
        pdf_bytes = s3.get_object(Bucket=os.environ["S3_BUCKET"], Key=pdf_key)["Body"].read()

        from pypdf import PdfReader

        with NamedTemporaryFile(suffix=".pdf") as f:
            f.write(pdf_bytes)
            f.flush()
            text = PdfReader(f.name).pages[0].extract_text() or ""
        assert "flatcraft://l_bracket/" in text
        # BETA-watermark footer (feedback@hart.crimea.ua) теж містить домен —
        # перевіряємо саме відсутність QR-permalink шляху, а не домену взагалі.
        assert "QR: https://hart.crimea.ua/f/" not in text


class TestSheetAndHolesGateParity:
    """Воркер дублює TS export-gate (CLAUDE.md §7 п.4, docs/07 §3, рішення
    yurii 2026-10-11: правило — від краю отвору, поле — від центру): та сама
    межа, що й API-gate. Остання лінія оборони, навіть якщо API обійдено."""

    def test_enclosed_shelf_t8_r5_900x300_sheet_exceeds_max_length_422(
        self, client: TestClient
    ) -> None:
        # flat_bottom + 2·BA + 2·(depth-tr) ≈ 1472мм > max_bend_length_mm=1000 для t=8.
        res = client.post(
            "/export",
            json={
                "template_slug": "enclosed_shelf",
                "parameters": {
                    **ENCLOSED_SHELF_VALID_PARAMS,
                    "width_mm": 900,
                    "depth_mm": 300,
                    "bend_radius_mm": 5,
                },
                "thickness_mm": 8,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422, res.text
        assert any(e["code"] == "SHEET_EXCEEDS_MAX_LENGTH" for e in res.json()["detail"])

    @pytest.mark.parametrize(
        ("distance_from_bend_mm", "diameter_mm", "expected_status"),
        [
            (9.4, 6, 422),  # a·t+R − 0.1 (край 6.4 < 6.5)
            (6.5, 6, 422),  # головний регресійний кейс — «від центру» пройшло б
            (9.5, 6, 200),  # рівно межа (край 6.5) — допустимо
            (9.5, 8, 422),  # той самий D, більший діаметр → край 5.5 < 6.5
            (30, 6, 200),  # контроль, далеко від межі
            # 9.7 - 6.4/2 = 6.499999999999999 (IEEE-754) — без допуску 1e-9
            # хибно блокує геометрично валідний отвір (рівно на межі 6.5).
            (9.7, 6.4, 200),
            (9.69, 6.4, 422),  # дійсно ближче за межу — допуск не маскує
        ],
    )
    def test_l_bracket_cold_rolled_hole_edge_parity(
        self,
        client: TestClient,
        aws_with_bucket: None,
        distance_from_bend_mm: float,
        diameter_mm: float,
        expected_status: int,
    ) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "l_bracket",
                "parameters": {
                    **VALID_PARAMS,
                    "holes": [
                        {
                            "leg": "A",
                            "distance_from_edge_mm": 20,
                            "distance_from_bend_mm": distance_from_bend_mm,
                            "diameter_mm": diameter_mm,
                        }
                    ],
                },
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == expected_status, res.text
        if expected_status == 422:
            assert any(e["code"] == "HOLE_TOO_CLOSE_TO_BEND" for e in res.json()["detail"])

    def test_l_bracket_aluminum_5754_d85_ok(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        # aluminum_5754 a=1.5, t=2, R=2.5 → мінімум від краю 5.5; D=8.5,Ø6 → край=5.5 — межа.
        res = client.post(
            "/export",
            json={
                "template_slug": "l_bracket",
                "parameters": {
                    **VALID_PARAMS,
                    "holes": [
                        {
                            "leg": "A",
                            "distance_from_edge_mm": 20,
                            "distance_from_bend_mm": 8.5,
                            "diameter_mm": 6,
                        }
                    ],
                },
                "thickness_mm": 2,
                "material_code": "aluminum_5754",
            },
        )
        assert res.status_code == 200, res.text

    def test_z_bracket_segment_t_d65_422(self, client: TestClient) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "z_bracket",
                "parameters": {
                    **Z_VALID_PARAMS,
                    "holes": [
                        {
                            "segment": "T",
                            "distance_from_edge_mm": 20,
                            "distance_from_bend_mm": 6.5,
                            "diameter_mm": 6,
                        }
                    ],
                },
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422, res.text
        assert any(e["code"] == "HOLE_TOO_CLOSE_TO_BEND" for e in res.json()["detail"])

    def test_z_bracket_segment_t_d12_control_ok(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "z_bracket",
                "parameters": {
                    **Z_VALID_PARAMS,
                    "holes": [
                        {
                            "segment": "T",
                            "distance_from_edge_mm": 20,
                            "distance_from_bend_mm": 12,
                            "diameter_mm": 6,
                        }
                    ],
                },
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 200, res.text

    def test_enclosed_shelf_t2_defaults_control_ok(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "enclosed_shelf",
                "parameters": ENCLOSED_SHELF_VALID_PARAMS,
                "thickness_mm": 2,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 200, res.text

    def test_export_id_без_base_url_env_теж_fallback(
        self, client: TestClient, aws_with_bucket: None, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.delenv("BASE_URL", raising=False)
        res = client.post(
            "/export",
            json={
                "template_slug": "l_bracket",
                "parameters": VALID_PARAMS,
                "thickness_mm": 2,
                "export_id": "00000000-1111-2222-3333-444444444444",
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 200, res.text
        pdf_key = res.json()["artifacts"]["pdf"]["s3_key"]
        s3 = boto3.client("s3", region_name="us-east-1")
        pdf_bytes = s3.get_object(Bucket=os.environ["S3_BUCKET"], Key=pdf_key)["Body"].read()

        from pypdf import PdfReader

        with NamedTemporaryFile(suffix=".pdf") as f:
            f.write(pdf_bytes)
            f.flush()
            text = PdfReader(f.name).pages[0].extract_text() or ""
        assert "flatcraft://l_bracket/" in text

    # z_bracket t=10 R=5 (max_bend_length_mm=1000), top=bottom=400, offset=205:
    # flat_sum = (400-15)+(205-15)+(400-15) = 960. BA(K) = (π/2)·(5+10·K).
    # K=0.4 (дефолт ExportRequest.k_factor) → BA=14.137166941154069,
    #   heightMm=960+2·BA=988.2743338823082 — на 11.7мм НИЖЧЕ межі 1000.
    # K=1.0 (явно у запиті, максимум дозволеного Field(le=1.0)) →
    #   BA=23.561944901923447, heightMm=1007.1238898038469 — на 7.1мм ВИЩЕ
    #   межі 1000. Обидва margin'и у межах мм, далеко від 1e-9-похибки
    #   округлення на самій межі 1000.0.
    #
    # Регресія: `server.py` передає `validate_export_sheet(...,
    # req.k_factor)` — якщо замінити на хардкод 0.4, гейт перевірятиме
    # габарит розгортки, яку насправді будує воркер з K=1.0 (запит явно
    # просить k_factor=1.0), застарілим K=0.4 — пропустить деталь, що по
    # факту НЕ влізає у верстат.
    def test_z_bracket_t10_явний_k_factor_1_0_перевищує_max_length_422(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        # `aws_with_bucket` тут не для happy-path — захист від мутанта, що
        # пропускає SHEET-гейт: якщо валідація помилково не впаде у 422, код
        # піде далі у CAD-генерацію + S3-upload, а без мокнутого `mock_aws()`
        # boto3 намагається реальний network call (у сендбоксі — зависання
        # на connect-timeout) замість швидкого AssertionError.
        res = client.post(
            "/export",
            json={
                "template_slug": "z_bracket",
                "parameters": {
                    **Z_VALID_PARAMS,
                    "top_flange_mm": 400,
                    "bottom_flange_mm": 400,
                    "offset_mm": 205,
                    "bend_radius_mm": 5,
                },
                "thickness_mm": 10,
                "k_factor": 1.0,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 422, res.text
        assert any(e["code"] == "SHEET_EXCEEDS_MAX_LENGTH" for e in res.json()["detail"])

    def test_z_bracket_t10_без_k_factor_контроль_не_перевищує_max_length(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        """Той самий запит без `k_factor` → Pydantic-дефолт 0.4 → габарит
        988.27мм < 1000мм → не SHEET_EXCEEDS_MAX_LENGTH (контроль до
        попереднього теста: різниця лише у k_factor)."""
        res = client.post(
            "/export",
            json={
                "template_slug": "z_bracket",
                "parameters": {
                    **Z_VALID_PARAMS,
                    "top_flange_mm": 400,
                    "bottom_flange_mm": 400,
                    "offset_mm": 205,
                    "bend_radius_mm": 5,
                },
                "thickness_mm": 10,
                "material_code": "cold_rolled_steel",
            },
        )
        assert res.status_code == 200, res.text
