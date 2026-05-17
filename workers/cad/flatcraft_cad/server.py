"""HTTP-сервер CAD-воркера (FastAPI).

Phase 2.7 sync flow: API ↔ HTTP ↔ Python ↔ MinIO/R2.
BullMQ async — Phase 2.8 (тоді цей же server лишається як fallback /
admin-trigger; основний шлях буде через bullmq-py listener).

Ендпоінти:
  GET  /health       — для health-check (k8s/docker-compose).
  POST /export       — генерує DXF + uploads + повертає presigned URL.
                       Тільки l_bracket у Phase 2.7; решта — 400.
"""

from __future__ import annotations

import os
import tempfile
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any, Literal

import boto3
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from flatcraft_cad.export.dxf import export_l_bracket_dxf
from flatcraft_cad.templates.l_bracket import LBracketBuildParameters, build_l_bracket
from flatcraft_cad.unfold import unfold_l_bracket

PRESIGN_EXPIRES_SEC = 3600


class ExportRequest(BaseModel):
    """Payload від API: уже Zod-валідований на TS-стороні, але pydantic
    лишається defense-in-depth (схема не дрейфує без оновлення обох)."""

    model_config = ConfigDict(extra="forbid")

    template_slug: Literal["l_bracket"]
    parameters: dict[str, Any]
    thickness_mm: float = Field(gt=0, le=10)
    # K-фактор — обчислюється на TS (cad-engine k-factor.ts), передається сюди.
    # Дефолт 0.4 для cold-rolled steel; Phase 3.x — справжній розрахунок з матеріалу.
    k_factor: float = Field(default=0.4, gt=0.0, le=1.0)


class ExportResponse(BaseModel):
    dxf_url: str
    bytes: int
    expires_at: str
    s3_key: str


def _build_app() -> FastAPI:
    app = FastAPI(title="flatcraft-cad", version="0.0.0")

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/export", response_model=ExportResponse)
    def export(req: ExportRequest) -> ExportResponse:
        if req.template_slug != "l_bracket":
            raise HTTPException(status_code=400, detail="unsupported_template")

        try:
            params = LBracketBuildParameters.model_validate(
                {**req.parameters, "thickness_mm": req.thickness_mm}
            )
        except Exception as exc:  # noqa: BLE001
            raise HTTPException(status_code=422, detail=f"invalid_parameters: {exc}") from exc

        # build тут не використовується безпосередньо — unfold має досить
        # параметрів через Pydantic-модель. Залишаємо виклик щоб ловити
        # ранні геометричні помилки (наприклад legA < t+r).
        _ = build_l_bracket(params)
        unfolded = unfold_l_bracket(params, req.k_factor)

        with tempfile.TemporaryDirectory() as td:
            out = export_l_bracket_dxf(
                unfolded,
                Path(td) / "out.dxf",
                bend_radius_mm=params.bend_radius_mm,
            )
            data = out.read_bytes()

        # endpoint_url=None → дефолтний AWS resolver, що дозволяє moto
        # перехоплювати boto3 у тестах. У dev/prod явно вказуємо MinIO/R2.
        endpoint_url = os.environ.get("S3_ENDPOINT") or None
        s3 = boto3.client(
            "s3",
            endpoint_url=endpoint_url,
            aws_access_key_id=os.environ["S3_ACCESS_KEY_ID"],
            aws_secret_access_key=os.environ["S3_SECRET_ACCESS_KEY"],
            region_name=os.environ.get("S3_REGION", "auto"),
        )
        bucket = os.environ["S3_BUCKET"]
        now = datetime.now(UTC)
        key = f"exports/{now.strftime('%Y/%m/%d')}/{now.strftime('%H%M%S_%f')}_l_bracket.dxf"
        s3.put_object(Bucket=bucket, Key=key, Body=data, ContentType="application/dxf")
        url = s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": bucket, "Key": key},
            ExpiresIn=PRESIGN_EXPIRES_SEC,
        )
        expires = (now + timedelta(seconds=PRESIGN_EXPIRES_SEC)).isoformat()
        return ExportResponse(dxf_url=url, bytes=len(data), expires_at=expires, s3_key=key)

    return app


app = _build_app()
