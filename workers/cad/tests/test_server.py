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
                "template_slug": "z_bracket",
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
    def test_успішний_експорт_заливає_dxf_у_бакет_і_повертає_presigned_url(
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
        assert body["bytes"] > 0
        assert body["s3_key"].startswith("exports/")
        assert body["s3_key"].endswith("_l_bracket.dxf")
        assert "expires_at" in body
        # boto3 за замовчуванням генерує SigV2 для S3 без region constraint:
        # ?Signature=...&Expires=... ; для SigV4 — X-Amz-Signature. Приймаємо обидва.
        assert "Signature=" in body["dxf_url"] or "X-Amz-Signature" in body["dxf_url"]
        assert "Expires=" in body["dxf_url"] or "X-Amz-Expires" in body["dxf_url"]

        s3 = boto3.client("s3", region_name="us-east-1")
        head = s3.head_object(Bucket=os.environ["S3_BUCKET"], Key=body["s3_key"])
        assert head["ContentLength"] == body["bytes"]
        assert head["ContentType"] == "application/dxf"

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
        assert a["bytes"] == b["bytes"]
        s3 = boto3.client("s3", region_name="us-east-1")
        body_a = s3.get_object(Bucket=os.environ["S3_BUCKET"], Key=a["s3_key"])["Body"].read()
        body_b = s3.get_object(Bucket=os.environ["S3_BUCKET"], Key=b["s3_key"])["Body"].read()
        assert body_a == body_b
