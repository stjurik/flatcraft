# syntax=docker/dockerfile:1.7
# Multi-stage Dockerfile для apps/web (Next.js 15 standalone).

ARG NODE_VERSION=20.11.0

# ─── deps ───────────────────────────────────────────────────────────────────
FROM node:${NODE_VERSION}-alpine AS deps
WORKDIR /app
RUN corepack enable
# CI=1 — lefthook prepare-hook у root package.json потребує git (немає в alpine).
ENV CI=1
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY apps/web/package.json ./apps/web/
COPY packages/types/package.json ./packages/types/
COPY packages/ui/package.json ./packages/ui/
COPY packages/cad-engine/package.json ./packages/cad-engine/
# --ignore-scripts: пропускаємо root prepare-hook (lefthook install потребує git).
RUN pnpm install --frozen-lockfile --ignore-scripts --filter @flatcraft/web...

# ─── builder ────────────────────────────────────────────────────────────────
FROM node:${NODE_VERSION}-alpine AS builder
WORKDIR /app
RUN corepack enable
COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/apps/web/node_modules ./apps/web/node_modules
COPY --from=deps /app/packages/types/node_modules ./packages/types/node_modules
COPY --from=deps /app/packages/ui/node_modules ./packages/ui/node_modules
COPY --from=deps /app/packages/cad-engine/node_modules ./packages/cad-engine/node_modules
COPY . .
# NEXT_PUBLIC_* інлайняться у клієнтський bundle на build-time (не runtime).
# Без цього браузер бере fallback localhost:4000 (apps/web/src/lib/api.ts).
ARG NEXT_PUBLIC_API_BASE_URL
ENV NEXT_PUBLIC_API_BASE_URL=${NEXT_PUBLIC_API_BASE_URL}
# Next.js standalone output вимагає `output: 'standalone'` у next.config.ts.
RUN pnpm --filter @flatcraft/web... build

# ─── runner: standalone bundle + static + public ────────────────────────────
FROM node:${NODE_VERSION}-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup --system --gid 1001 nodejs && adduser --system --uid 1001 nextjs

# Standalone output вже включає мінімальний node_modules з усіма залежностями.
COPY --from=builder --chown=nextjs:nodejs /app/apps/web/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/apps/web/.next/static ./apps/web/.next/static
COPY --from=builder --chown=nextjs:nodejs /app/apps/web/public ./apps/web/public

ARG GIT_COMMIT=local
ARG APP_VERSION=staging
LABEL org.opencontainers.image.source="https://github.com/stjurik/flatcraft" \
      org.opencontainers.image.title="flatcraft-web" \
      org.opencontainers.image.description="Next.js 15 frontend для flatcraft" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}" \
      org.opencontainers.image.licenses="MIT"

USER nextjs
EXPOSE 3000
ENV PORT=3000 HOSTNAME="0.0.0.0"
CMD ["node", "apps/web/server.js"]
