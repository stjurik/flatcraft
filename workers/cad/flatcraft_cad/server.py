"""HTTP-сервер CAD-воркера (FastAPI).

Phase 2.7 sync flow: API ↔ HTTP ↔ Python ↔ MinIO/R2.
Phase 2.9: повертає одночасно DXF + PDF artifacts (одним викликом —
один CadQuery-обчислення, два upload + два presigned URL).

Ендпоінти:
  GET  /health       — health-check (k8s/docker-compose).
  POST /export       — генерує DXF+PDF, заливає у S3, повертає
                       presigned URL для обох. Тільки l_bracket.
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
from flatcraft_cad.export.pdf import export_l_bracket_pdf
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


class ExportArtifact(BaseModel):
    """Один артефакт (DXF або PDF). Поля — те ж, що ExportArtifactSchema у
    `packages/types/domain/export.ts`."""

    url: str
    bytes: int
    expires_at: str
    s3_key: str


class ExportArtifacts(BaseModel):
    dxf: ExportArtifact
    pdf: ExportArtifact


class ExportResponse(BaseModel):
    artifacts: ExportArtifacts


def _upload(s3: Any, bucket: str, key: str, data: bytes, content_type: str) -> ExportArtifact:
    s3.put_object(Bucket=bucket, Key=key, Body=data, ContentType=content_type)
    url = s3.generate_presigned_url(
        "get_object",
        Params={"Bucket": bucket, "Key": key},
        ExpiresIn=PRESIGN_EXPIRES_SEC,
    )
    expires = (datetime.now(UTC) + timedelta(seconds=PRESIGN_EXPIRES_SEC)).isoformat()
    return ExportArtifact(url=url, bytes=len(data), expires_at=expires, s3_key=key)


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
            dxf_path = export_l_bracket_dxf(
                unfolded,
                Path(td) / "out.dxf",
                bend_radius_mm=params.bend_radius_mm,
            )
            dxf_data = dxf_path.read_bytes()

            pdf_path = export_l_bracket_pdf(params, unfolded, Path(td) / "out.pdf")
            pdf_data = pdf_path.read_bytes()

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
        date_path = now.strftime("%Y/%m/%d")
        ts = now.strftime("%H%M%S_%f")
        dxf_key = f"exports/{date_path}/{ts}_l_bracket.dxf"
        pdf_key = f"exports/{date_path}/{ts}_l_bracket.pdf"

        artifacts = ExportArtifacts(
            dxf=_upload(s3, bucket, dxf_key, dxf_data, "application/dxf"),
            pdf=_upload(s3, bucket, pdf_key, pdf_data, "application/pdf"),
        )
        return ExportResponse(artifacts=artifacts)

    return app


app = _build_app()
