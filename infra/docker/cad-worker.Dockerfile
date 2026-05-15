# syntax=docker/dockerfile:1.7
# Dockerfile для workers/cad (Python 3.12 + CadQuery).
# CadQuery потребує OpenCascade — використовуємо офіційний образ або встановлюємо через conda.

FROM python:3.12-slim-bookworm AS builder

# CadQuery з OpenCascade потребує build-essential і кілька системних пакетів
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libgl1 \
    libglu1-mesa \
    libxrender1 \
    libxext6 \
    libxi6 \
    libsm6 \
    libfontconfig1 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Встановлюємо uv (швидкий пакетний менеджер)
COPY --from=ghcr.io/astral-sh/uv:0.4.18 /uv /usr/local/bin/uv

WORKDIR /app
COPY workers/cad/pyproject.toml workers/cad/uv.lock* ./
RUN uv sync --frozen --no-dev

COPY workers/cad/ ./
COPY packages/cad-engine/data/bend-machine-esi.yaml /app/data/bend-machine-esi.yaml

# ─── Runtime ───────────────────────────────────────────────────────────────
FROM python:3.12-slim-bookworm AS runner

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

# Worker слухає чергу. Healthcheck — мінімальний HTTP на 8080.
EXPOSE 8080
CMD ["python", "-m", "flatcraft_cad.worker"]
