"""HTTP-сервер CAD-воркера (FastAPI).

Phase 2.7: sync API ↔ Python ↔ MinIO/R2.
Phase 2.9: повертає DXF + PDF artifacts одним викликом.
Phase 2.10: підтримка multiple slugs (l_bracket, z_bracket).
"""

from __future__ import annotations

import os
import tempfile
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any, Literal
from uuid import UUID

import boto3
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from flatcraft_cad.export.dxf import (
    export_corner_angle_dxf,
    export_enclosed_shelf_dxf,
    export_l_bracket_dxf,
    export_perforated_panel_dxf,
    export_wall_shelf_dxf,
    export_z_bracket_dxf,
)
from flatcraft_cad.export.pdf import (
    export_corner_angle_pdf,
    export_enclosed_shelf_pdf,
    export_l_bracket_pdf,
    export_perforated_panel_pdf,
    export_wall_shelf_pdf,
    export_z_bracket_pdf,
)
from flatcraft_cad.sentry_setup import init_sentry
from flatcraft_cad.templates.corner_angle import CornerAngleBuildParameters, build_corner_angle
from flatcraft_cad.templates.enclosed_shelf import (
    EnclosedShelfBuildParameters,
    build_enclosed_shelf,
)
from flatcraft_cad.templates.l_bracket import LBracketBuildParameters, build_l_bracket
from flatcraft_cad.templates.perforated_panel import (
    PerforatedPanelBuildParameters,
    build_perforated_panel,
)
from flatcraft_cad.templates.wall_shelf import WallShelfBuildParameters, build_wall_shelf
from flatcraft_cad.templates.z_bracket import ZBracketBuildParameters, build_z_bracket
from flatcraft_cad.unfold import (
    unfold_corner_angle,
    unfold_enclosed_shelf,
    unfold_l_bracket,
    unfold_perforated_panel,
    unfold_wall_shelf,
    unfold_z_bracket,
)
from flatcraft_cad.validate import (
    validate_export,
    validate_export_perforation,
    validate_export_profile,
)

PRESIGN_EXPIRES_SEC = 3600

# Допустимі slugs — підтягуємо з типу для безпеки.
TemplateSlug = Literal[
    "l_bracket",
    "z_bracket",
    "corner_angle",
    "wall_shelf",
    "perforated_panel",
    "enclosed_shelf",
]


class ExportRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    template_slug: TemplateSlug
    parameters: dict[str, Any]
    thickness_mm: float = Field(gt=0, le=10)
    k_factor: float = Field(default=0.4, gt=0.0, le=1.0)
    # Issue #70: генерується apps/api (== persisted exports.id) перед форвардом
    # сюди. Дозволяє QR у PDF вести на {BASE_URL}/f/{export_id} замість
    # непрацюючого fallback-scheme flatcraft://<slug>/<article>.
    export_id: UUID | None = None


def _permalink_url(export_id: UUID | None) -> str | None:
    """`{BASE_URL}/f/{export_id}` для QR у PDF, або None (fallback у export/pdf.py)."""
    if export_id is None:
        return None
    base_url = os.environ.get("BASE_URL")
    if not base_url:
        return None
    return f"{base_url.rstrip('/')}/f/{export_id}"


class ExportArtifact(BaseModel):
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


def _generate_l_bracket(req: ExportRequest, tmpdir: Path) -> tuple[bytes, bytes]:
    """Повертає (dxf_bytes, pdf_bytes) для L-bracket."""
    try:
        params = LBracketBuildParameters.model_validate(
            {**req.parameters, "thickness_mm": req.thickness_mm},
        )
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=422, detail=f"invalid_parameters: {exc}") from exc

    solid = build_l_bracket(params)
    unfolded = unfold_l_bracket(params, req.k_factor)
    dxf = export_l_bracket_dxf(
        unfolded,
        tmpdir / "out.dxf",
        bend_radius_mm=params.bend_radius_mm,
        bend_direction=params.bend_direction,
    ).read_bytes()
    pdf = export_l_bracket_pdf(
        params,
        unfolded,
        tmpdir / "out.pdf",
        solid=solid,
        permalink_url=_permalink_url(req.export_id),
    ).read_bytes()
    return dxf, pdf


def _generate_z_bracket(req: ExportRequest, tmpdir: Path) -> tuple[bytes, bytes]:
    """Повертає (dxf_bytes, pdf_bytes) для Z-bracket."""
    try:
        params = ZBracketBuildParameters.model_validate(
            {**req.parameters, "thickness_mm": req.thickness_mm},
        )
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=422, detail=f"invalid_parameters: {exc}") from exc

    solid = build_z_bracket(params)
    unfolded = unfold_z_bracket(params, req.k_factor)
    dxf = export_z_bracket_dxf(
        unfolded,
        tmpdir / "out.dxf",
        bend_radius_mm=params.bend_radius_mm,
        bend_directions=tuple(b.direction for b in params.bends),
    ).read_bytes()
    pdf = export_z_bracket_pdf(
        params,
        unfolded,
        tmpdir / "out.pdf",
        solid=solid,
        permalink_url=_permalink_url(req.export_id),
    ).read_bytes()
    return dxf, pdf


def _generate_corner_angle(req: ExportRequest, tmpdir: Path) -> tuple[bytes, bytes]:
    """Повертає (dxf_bytes, pdf_bytes) для corner_angle."""
    try:
        params = CornerAngleBuildParameters.model_validate(
            {**req.parameters, "thickness_mm": req.thickness_mm},
        )
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=422, detail=f"invalid_parameters: {exc}") from exc

    solid = build_corner_angle(params)
    unfolded = unfold_corner_angle(params, req.k_factor)
    dxf = export_corner_angle_dxf(
        unfolded,
        tmpdir / "out.dxf",
        bend_radius_mm=params.bend_radius_mm,
        bend_direction=params.bend_direction,
    ).read_bytes()
    pdf = export_corner_angle_pdf(
        params,
        unfolded,
        tmpdir / "out.pdf",
        solid=solid,
        permalink_url=_permalink_url(req.export_id),
    ).read_bytes()
    return dxf, pdf


def _generate_wall_shelf(req: ExportRequest, tmpdir: Path) -> tuple[bytes, bytes]:
    """Повертає (dxf_bytes, pdf_bytes) для wall_shelf."""
    try:
        params = WallShelfBuildParameters.model_validate(
            {**req.parameters, "thickness_mm": req.thickness_mm},
        )
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=422, detail=f"invalid_parameters: {exc}") from exc

    solid = build_wall_shelf(params)
    unfolded = unfold_wall_shelf(params, req.k_factor)
    dxf = export_wall_shelf_dxf(
        unfolded,
        tmpdir / "out.dxf",
        bend_radius_mm=params.bend_radius_mm,
        bend_directions=tuple(b.direction for b in params.bends),
    ).read_bytes()
    pdf = export_wall_shelf_pdf(
        params,
        unfolded,
        tmpdir / "out.pdf",
        solid=solid,
        permalink_url=_permalink_url(req.export_id),
    ).read_bytes()
    return dxf, pdf


def _generate_perforated_panel(req: ExportRequest, tmpdir: Path) -> tuple[bytes, bytes]:
    """Перфо-монтажна панель (ребриста, ADR-030/031): build→лоток, cross-unfold, DXF/PDF.

    Має гиби (4 ребра) → unfold приймає k_factor (паритет з enclosed_shelf).
    Форма перфо-отвору (круг/квадрат) — параметр `hole_shape`.
    """
    try:
        params = PerforatedPanelBuildParameters.model_validate(
            {**req.parameters, "thickness_mm": req.thickness_mm},
        )
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=422, detail=f"invalid_parameters: {exc}") from exc

    solid = build_perforated_panel(params)
    unfolded = unfold_perforated_panel(params, req.k_factor)
    dxf = export_perforated_panel_dxf(unfolded, tmpdir / "out.dxf").read_bytes()
    pdf = export_perforated_panel_pdf(
        params,
        unfolded,
        tmpdir / "out.pdf",
        solid=solid,
        permalink_url=_permalink_url(req.export_id),
    ).read_bytes()
    return dxf, pdf


def _generate_enclosed_shelf(req: ExportRequest, tmpdir: Path) -> tuple[bytes, bytes]:
    """Phase 3.0 PR 7c (ADR-027 Рішення 5): enclosed_shelf cross-pipeline.

    Окремий handler з власним 2D unfold і cross-shape DXF (одна LWPOLYLINE
    cross + 3-4 BEND_LINES). PDF — simplified без isometric.
    """
    try:
        params = EnclosedShelfBuildParameters.model_validate(
            {**req.parameters, "thickness_mm": req.thickness_mm},
        )
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=422, detail=f"invalid_parameters: {exc}") from exc

    _ = build_enclosed_shelf(params)  # 3D-валідація геометрії, у PDF поки не вживаємо
    unfolded = unfold_enclosed_shelf(params, req.k_factor)
    dxf = export_enclosed_shelf_dxf(unfolded, tmpdir / "out.dxf").read_bytes()
    pdf = export_enclosed_shelf_pdf(
        params, unfolded, tmpdir / "out.pdf", permalink_url=_permalink_url(req.export_id)
    ).read_bytes()
    return dxf, pdf


def _build_app() -> FastAPI:
    init_sentry()  # ADR-032: no-op без SENTRY_DSN (dev/CI/тести)
    app = FastAPI(title="flatcraft-cad", version="0.0.0")

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/export", response_model=ExportResponse)
    def export(req: ExportRequest) -> ExportResponse:
        # ADR-019/026: parity-валідація профілю+гиба ДО будь-якої CAD-операції /
        # S3-запису. Остання лінія оборони — навіть якщо API-gate обійдено.
        errors = [
            *validate_export_profile(req.template_slug, req.parameters, req.thickness_mm),
            *validate_export(req.template_slug, req.parameters, req.thickness_mm),
            *validate_export_perforation(req.template_slug, req.parameters),
        ]
        if errors:
            raise HTTPException(status_code=422, detail=errors)

        with tempfile.TemporaryDirectory() as td:
            tmpdir = Path(td)
            if req.template_slug == "l_bracket":
                dxf_data, pdf_data = _generate_l_bracket(req, tmpdir)
            elif req.template_slug == "z_bracket":
                dxf_data, pdf_data = _generate_z_bracket(req, tmpdir)
            elif req.template_slug == "corner_angle":
                dxf_data, pdf_data = _generate_corner_angle(req, tmpdir)
            elif req.template_slug == "wall_shelf":
                dxf_data, pdf_data = _generate_wall_shelf(req, tmpdir)
            elif req.template_slug == "perforated_panel":
                dxf_data, pdf_data = _generate_perforated_panel(req, tmpdir)
            elif req.template_slug == "enclosed_shelf":
                dxf_data, pdf_data = _generate_enclosed_shelf(req, tmpdir)
            else:
                # Pydantic Literal вже відсіює інші, але type-narrow для mypy.
                raise HTTPException(status_code=400, detail="unsupported_template")

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
        dxf_key = f"exports/{date_path}/{ts}_{req.template_slug}.dxf"
        pdf_key = f"exports/{date_path}/{ts}_{req.template_slug}.pdf"

        artifacts = ExportArtifacts(
            dxf=_upload(s3, bucket, dxf_key, dxf_data, "application/dxf"),
            pdf=_upload(s3, bucket, pdf_key, pdf_data, "application/pdf"),
        )
        return ExportResponse(artifacts=artifacts)

    return app


app = _build_app()
