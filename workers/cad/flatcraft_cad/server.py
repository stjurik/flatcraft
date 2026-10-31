"""HTTP-сервер CAD-воркера (FastAPI).

Phase 2.7: sync API ↔ Python ↔ MinIO/R2.
Phase 2.9: повертає DXF + PDF artifacts одним викликом.
Phase 2.10: підтримка multiple slugs (l_bracket, z_bracket).
"""

from __future__ import annotations

import math
import os
import tempfile
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any, Literal
from uuid import UUID

import boto3
from fastapi import FastAPI, HTTPException, Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field, field_validator

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
from flatcraft_cad.k_factor import compute_k_factor
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
    sanitize_for_gates,
    validate_export,
    validate_export_holes,
    validate_export_perforation,
    validate_export_profile,
    validate_export_sheet,
    validate_export_types,
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
    # Issue #70: генерується apps/api (== persisted exports.id) перед форвардом
    # сюди. Дозволяє QR у PDF вести на {BASE_URL}/f/{export_id} замість
    # непрацюючого fallback-scheme flatcraft://<slug>/<article>.
    export_id: UUID | None = None
    # Рішення Архітектора 2026-10-13 (заміняє рішення yurii 2026-10-06, яке
    # зробило поле опційним; ADR-043): material_code ОБОВ'ЯЗКОВИЙ — потрібен
    # для matrix-валідації матеріалу (validate_bend), hole-to-bend-distance
    # parity (coefficient_by_material) — `validate_export`/
    # `validate_export_holes`/`validate_export_sheet` — і (рішення yurii
    # 2026-10-14 «1а», issue #246) для K-фактора розгортки: `compute_k_factor`
    # нижче бере базове K матеріалу з `k_factor.default_by_material`
    # ПЕРЕД побудовою кожної розгортки (`unfold_*`), тож material_code тепер
    # ВПЛИВАЄ на геометрію DXF/PDF, не лише на валідацію.
    # API (apps/api) уже завжди його передає (Zod-схема вимагає). Відсутнє
    # поле → 422 від Pydantic-схеми цього ExportRequest.
    material_code: str

    @field_validator("thickness_mm", mode="before")
    @classmethod
    def _thickness_mm_must_not_be_bool(cls, value: Any) -> Any:
        """Доробка 049 (issue #274, рецензія Flash на PR #287): Pydantic
        лояльно коерсує `bool` у `1.0`/`0.0` для `float`-поля (той самий
        контрприклад Argon, що й для числових полів у `parameters` —
        `validate/types.py::_is_number`), тож `thickness_mm: true` без цієї
        перевірки тихо ставало товщиною 1 мм замість 422."""
        if isinstance(value, bool):
            raise ValueError("thickness_mm має бути числом, не логічним значенням (true/false).")
        return value


_BUILD_PARAMS_BY_SLUG: dict[TemplateSlug, type[BaseModel]] = {
    "l_bracket": LBracketBuildParameters,
    "z_bracket": ZBracketBuildParameters,
    "corner_angle": CornerAngleBuildParameters,
    "wall_shelf": WallShelfBuildParameters,
    "perforated_panel": PerforatedPanelBuildParameters,
    "enclosed_shelf": EnclosedShelfBuildParameters,
}


def _params_with_defaults(
    slug: TemplateSlug, parameters: dict[str, Any], thickness_mm: float
) -> dict[str, Any]:
    """Issue #257 п.1: доповнює сирі `parameters` Pydantic-дефолтами шаблону.

    `validate/*.py`-гейти читають `parameters[...]` напряму: без цієї функції
    відсутнє `bend_angle_deg` (wall_shelf) чи `bend_radius_mm`
    (perforated_panel) робить їх сліпими (KeyError → []), а Pydantic у
    `_generate_*` тим часом підставляє дефолт і будує деталь — гейт і
    генерація бачать різні параметри. `req.thickness_mm` перемагає поле
    `thickness_mm` у `parameters` (той самий порядок, що й у `_generate_*`).

    Невалідні parameters (модель кидає) → повертаємо parameters як є: 422
    дасть генерація (`_generate_*`), як і зараз. Поля моделі (з приведеними
    типами й дефолтами, `thickness_mm` = req) мають пріоритет над сирими —
    інакше рядок "80" з `parameters` повертався б у гейт, ламав арифметику
    sheet-гейту (TypeError → []) і давав 200 замість 422 (контрприклади
    Gemini 4 Argon до PR #273). Сирі поля, яких модель не знає (напр.
    `holes` у l_bracket), зберігаються.
    """
    model_cls = _BUILD_PARAMS_BY_SLUG[slug]
    try:
        model = model_cls.model_validate({**parameters, "thickness_mm": thickness_mm})
    except Exception:  # noqa: BLE001
        return parameters
    return {**parameters, **model.model_dump(by_alias=True), "thickness_mm": thickness_mm}


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


def _k_factor_or_422(req: ExportRequest, inner_radius_mm: float) -> float:
    """K за матеріалом (ADR-043); ValueError (матеріал без K у YAML, R/t поза
    діапазонами) — 422 з причиною, а не 500 (рецензія Flash до PR #260)."""
    try:
        return compute_k_factor(req.material_code, req.thickness_mm, inner_radius_mm)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=f"invalid_parameters: {exc}") from exc


def _generate_l_bracket(req: ExportRequest, tmpdir: Path) -> tuple[bytes, bytes]:
    """Повертає (dxf_bytes, pdf_bytes) для L-bracket."""
    try:
        params = LBracketBuildParameters.model_validate(
            {**req.parameters, "thickness_mm": req.thickness_mm},
        )
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=422, detail=f"invalid_parameters: {exc}") from exc

    k_factor = _k_factor_or_422(req, params.bend_radius_mm)
    solid = build_l_bracket(params)
    unfolded = unfold_l_bracket(params, k_factor)
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
        material_label=req.material_code,
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

    k_factor = _k_factor_or_422(req, params.bend_radius_mm)
    solid = build_z_bracket(params)
    unfolded = unfold_z_bracket(params, k_factor)
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
        material_label=req.material_code,
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

    k_factor = _k_factor_or_422(req, params.bend_radius_mm)
    solid = build_corner_angle(params)
    unfolded = unfold_corner_angle(params, k_factor)
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
        material_label=req.material_code,
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

    k_factor = _k_factor_or_422(req, params.bend_radius_mm)
    solid = build_wall_shelf(params)
    unfolded = unfold_wall_shelf(params, k_factor)
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
        material_label=req.material_code,
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

    k_factor = _k_factor_or_422(req, params.bend_radius_mm)
    solid = build_perforated_panel(params)
    unfolded = unfold_perforated_panel(params, k_factor)
    dxf = export_perforated_panel_dxf(unfolded, tmpdir / "out.dxf").read_bytes()
    pdf = export_perforated_panel_pdf(
        params,
        unfolded,
        tmpdir / "out.pdf",
        solid=solid,
        permalink_url=_permalink_url(req.export_id),
        material_label=req.material_code,
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

    k_factor = _k_factor_or_422(req, params.bend_radius_mm)
    _ = build_enclosed_shelf(params)  # 3D-валідація геометрії, у PDF поки не вживаємо
    unfolded = unfold_enclosed_shelf(params, k_factor)
    dxf = export_enclosed_shelf_dxf(unfolded, tmpdir / "out.dxf").read_bytes()
    pdf = export_enclosed_shelf_pdf(
        params,
        unfolded,
        tmpdir / "out.pdf",
        permalink_url=_permalink_url(req.export_id),
        material_label=req.material_code,
    ).read_bytes()
    return dxf, pdf


def _json_safe(value: Any) -> Any:
    """Доробка 049 (issue #274, рецензія Flash на PR #287): рекурсивно
    замінює NaN/±Infinity рядком перед JSON-серіалізацією 422-відповіді.

    `thickness_mm` як JSON-літерал `NaN`/`Infinity` коректно провалює
    Pydantic-обмеження `gt`/`le` (422), але `RequestValidationError.errors()`
    ехо-ить сире значення у `input` того самого error dict. Starlette
    `JSONResponse.render` викликає `json.dumps(..., allow_nan=False)` —
    без санітизації нескінченне/NaN значення в `detail` валить ВІДПОВІДЬ
    (не запит) у 500 ДО того, як клієнт побачить задуманий 422.
    """
    if isinstance(value, float) and not math.isfinite(value):
        if math.isnan(value):
            return "NaN"
        return "Infinity" if value > 0 else "-Infinity"
    if isinstance(value, dict):
        return {key: _json_safe(v) for key, v in value.items()}
    if isinstance(value, list):
        return [_json_safe(v) for v in value]
    return value


def _build_app() -> FastAPI:
    init_sentry()  # ADR-032: no-op без SENTRY_DSN (dev/CI/тести)
    app = FastAPI(title="flatcraft-cad", version="0.0.0")

    @app.exception_handler(RequestValidationError)
    def _on_request_validation_error(
        _request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        """Паритет з дефолтним хендлером FastAPI (той самий shape `detail`),
        але з `_json_safe` — інакше NaN/Infinity у сирому вхідному значенні
        (`thickness_mm`) валить саму 422-відповідь у 500 (докладніше —
        `_json_safe`)."""
        return JSONResponse(
            status_code=422,
            content={"detail": _json_safe(jsonable_encoder(exc.errors()))},
        )

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/export", response_model=ExportResponse)
    def export(req: ExportRequest) -> ExportResponse:
        # ADR-019/026: parity-валідація профілю+гиба ДО будь-якої CAD-операції /
        # S3-запису. Остання лінія оборони — навіть якщо API-gate обійдено.
        # Issue #257 п.1: гейти рахують параметри ПІСЛЯ Pydantic-дефолтів
        # шаблону (bend_angle_deg/bend_radius_mm і т.п.), інакше вони сліпі до
        # того, що з повними параметрами відхиляють.
        # Issue #274: тип перевіряється на СИРИХ `req.parameters`, ДО злиття з
        # Pydantic-дефолтами — `_params_with_defaults` лояльно приводить
        # bool/рядок-число до float (навіть якщо результат випадково валідний
        # за діапазоном), тож перевірка типу після злиття пропустила б
        # `bend_radius_mm: true`. Поля з помилкою типу нейтралізуються
        # (`sanitize_for_gates`) перед тим, як потрапити у решту гейтів —
        # інакше `validate/bend.py`/`validate/perforation.py` впали б на
        # `float()` без try/except (500 замість 422).
        type_errors = validate_export_types(req.template_slug, req.parameters)
        gate_params = _params_with_defaults(req.template_slug, req.parameters, req.thickness_mm)
        gate_params = sanitize_for_gates(gate_params, type_errors)
        errors = [
            *type_errors,
            *validate_export_profile(req.template_slug, gate_params, req.thickness_mm),
            *validate_export(req.template_slug, gate_params, req.thickness_mm, req.material_code),
            *validate_export_perforation(req.template_slug, gate_params),
            *validate_export_sheet(
                req.template_slug, gate_params, req.thickness_mm, req.material_code
            ),
            *validate_export_holes(
                req.template_slug, gate_params, req.thickness_mm, req.material_code
            ),
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
