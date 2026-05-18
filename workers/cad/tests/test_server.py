"""Тести FastAPI /export — Pydantic-валідація + flow з mock'ed S3."""

from __future__ import annotations

import os
from collections.abc import Iterator

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


class TestExportValidation:
    def test_невалідний_template_slug_422(self, client: TestClient) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "perforated_panel",
                "parameters": VALID_PARAMS,
                "thickness_mm": 2,
            },
        )
        assert res.status_code == 422

    def test_leg_a_за_межами_422(self, client: TestClient) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "l_bracket",
                "parameters": {**VALID_PARAMS, "legA_mm": 10},
                "thickness_mm": 2,
            },
        )
        assert res.status_code == 422

    def test_невідоме_поле_у_request_422(self, client: TestClient) -> None:
        res = client.post(
            "/export",
            json={
                "template_slug": "l_bracket",
                "parameters": VALID_PARAMS,
                "thickness_mm": 2,
                "extra_garbage": "x",
            },
        )
        assert res.status_code == 422


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
            },
        )
        assert res.status_code == 422

    def test_l_і_z_bracket_дають_різні_артефакти(
        self, client: TestClient, aws_with_bucket: None
    ) -> None:
        l_res = client.post(
            "/export",
            json={
                "template_slug": "l_bracket",
                "parameters": VALID_PARAMS,
                "thickness_mm": 2,
            },
        ).json()
        z_res = client.post(
            "/export",
            json={
                "template_slug": "z_bracket",
                "parameters": Z_VALID_PARAMS,
                "thickness_mm": 2,
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
