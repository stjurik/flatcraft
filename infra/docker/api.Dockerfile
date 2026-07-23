# syntax=docker/dockerfile:1.7
# Multi-stage Dockerfile для apps/api (Fastify + TypeScript).

ARG NODE_VERSION=20.11.0

# ─── deps: install з повним workspace + lockfile, для кешування ─────────────
FROM node:${NODE_VERSION}-alpine AS deps
WORKDIR /app
RUN corepack enable
# CI=1 — щоб root prepare-hook `lefthook install` був no-op у контейнері
# (lefthook потребує git, якого в alpine немає, і git hooks нам в image все одно не треба).
ENV CI=1
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY apps/api/package.json ./apps/api/
COPY packages/types/package.json ./packages/types/
COPY packages/db/package.json ./packages/db/
# cad-engine — нова залежність api (Hotfix 2.10.e: серверний validateBend gate).
COPY packages/cad-engine/package.json ./packages/cad-engine/
# templates — нова залежність api (Run 7 Registry Track, ADR-033).
COPY packages/templates/package.json ./packages/templates/
# --ignore-scripts: пропускаємо root prepare-hook (lefthook install потребує git);
# ssh2 необов'язковий native binding теж пропускається — fallback на pure-JS crypto.
RUN pnpm install --frozen-lockfile --ignore-scripts --filter @flatcraft/api...

# ─── builder: TS → JS, далі pnpm deploy у prod-вузький дерев ────────────────
FROM node:${NODE_VERSION}-alpine AS builder
WORKDIR /app
RUN corepack enable
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/apps/api/node_modules ./apps/api/node_modules
COPY --from=deps /app/packages/types/node_modules ./packages/types/node_modules
COPY --from=deps /app/packages/db/node_modules ./packages/db/node_modules
COPY --from=deps /app/packages/cad-engine/node_modules ./packages/cad-engine/node_modules
COPY --from=deps /app/packages/templates/node_modules ./packages/templates/node_modules
COPY . .
# Build з усіма workspace-deps (`...` суфікс): types → db → api у правильному порядку.
RUN pnpm --filter @flatcraft/api... build && \
    pnpm deploy --filter @flatcraft/api --prod --ignore-scripts /tmp/prod

# ─── runner: тонкий image ───────────────────────────────────────────────────
FROM node:${NODE_VERSION}-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup --system --gid 1001 nodejs && adduser --system --uid 1001 fastify
COPY --from=builder --chown=fastify:nodejs /tmp/prod ./
# Entrypoint застосовує міграції + seed перед стартом сервера (див. сам скрипт).
COPY --chown=fastify:nodejs infra/docker/api-entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ARG GIT_COMMIT=local
ARG APP_VERSION=staging
LABEL org.opencontainers.image.source="https://github.com/stjurik/flatcraft" \
      org.opencontainers.image.title="flatcraft-api" \
      org.opencontainers.image.description="Fastify REST API для flatcraft" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.licenses="MIT"

USER fastify
EXPOSE 4000
ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["node", "dist/server.js"]
