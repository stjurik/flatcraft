# syntax=docker/dockerfile:1.7
# Multi-stage Dockerfile для workers/cad (Python 3.12 + CadQuery + FastAPI).
# CadQuery тягне OpenCascade — потрібні libgl/libfontconfig системно.

ARG PYTHON_VERSION=3.12

# ─── Builder ────────────────────────────────────────────────────────────────
FROM python:${PYTHON_VERSION}-slim-bookworm AS builder

# Системні залежності для OpenCascade + curl для uv installer-як-захист
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libgl1 \
    libglu1-mesa \
    libxrender1 \
    libxext6 \
    libxi6 \
    libsm6 \
    libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*

# uv для швидкого pip-резолва (тримаємо pinned версію)
COPY --from=ghcr.io/astral-sh/uv:0.4.18 /uv /usr/local/bin/uv

WORKDIR /app
COPY workers/cad/pyproject.toml workers/cad/uv.lock* workers/cad/README.md ./
# --frozen: respect lockfile. --no-dev: пропустити [dependency-groups.dev] групу.
RUN uv sync --frozen --no-dev

COPY workers/cad/flatcraft_cad ./flatcraft_cad
COPY packages/cad-engine/data/bend-machine-esi.yaml /app/data/bend-machine-esi.yaml

# ─── Runtime ────────────────────────────────────────────────────────────────
FROM python:${PYTHON_VERSION}-slim-bookworm AS runner

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    libglu1-mesa \
    libxrender1 \
    libxext6 \
    libxi6 \
    libsm6 \
    libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --system --uid 1001 --create-home cad
USER cad

WORKDIR /app
COPY --from=builder --chown=cad:cad /app /app
ENV PATH="/app/.venv/bin:$PATH"
ENV BEND_MACHINE_SPEC_PATH=/app/data/bend-machine-esi.yaml

# OCI labels — CI підставляє GIT_COMMIT і APP_VERSION з GH metadata.
ARG GIT_COMMIT=local
ARG APP_VERSION=staging
LABEL org.opencontainers.image.source="https://github.com/stjurik/flatcraft" \
      org.opencontainers.image.title="flatcraft-cad-worker" \
      org.opencontainers.image.description="CadQuery + FastAPI worker для DXF/PDF/STEP експорту" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.licenses="MIT"

EXPOSE 8080
# uvicorn — production ASGI сервер. server.py експозить `app` на module-level.
# Workers=1, бо CAD_WORKER_CONCURRENCY=1 (ADR-011, 4 GB RAM constraint).
CMD ["uvicorn", "flatcraft_cad.server:app", "--host", "0.0.0.0", "--port", "8080", "--workers", "1"]
