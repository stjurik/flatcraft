# syntax=docker/dockerfile:1.7
# Multi-stage Dockerfile для apps/api (Fastify).

ARG NODE_VERSION=20.11.0

FROM node:${NODE_VERSION}-alpine AS deps
WORKDIR /app
RUN corepack enable
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./
COPY apps/api/package.json ./apps/api/
COPY packages/types/package.json ./packages/types/
COPY packages/db/package.json ./packages/db/
RUN pnpm install --frozen-lockfile --filter @flatcraft/api...

FROM node:${NODE_VERSION}-alpine AS builder
WORKDIR /app
RUN corepack enable
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN pnpm --filter @flatcraft/api... build && \
    pnpm deploy --filter @flatcraft/api --prod /tmp/prod

FROM node:${NODE_VERSION}-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup --system --gid 1001 nodejs && adduser --system --uid 1001 fastify
COPY --from=builder --chown=fastify:nodejs /tmp/prod ./
USER fastify
EXPOSE 4000
CMD ["node", "dist/server.js"]
