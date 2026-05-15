# @flatcraft/api

Fastify backend. Див. `AGENTS.md`.

## Запуск

```bash
pnpm --filter @flatcraft/api dev
```

Відкрийте http://localhost:4000/healthz.

## Перші файли (Phase 0)

```
src/server.ts                 # Fastify init + plugins
src/plugins/sentry.ts
src/plugins/auth.ts
src/plugins/rate-limit.ts
src/plugins/swagger.ts        # OpenAPI auto-doc
src/routes/health.ts
src/routes/auth/*.ts
src/routes/templates/*.ts
src/lib/queue.ts              # BullMQ producer
src/lib/r2.ts                 # S3 client
```

## OpenAPI

Генерується з Zod-схем у CI:

```bash
pnpm --filter @flatcraft/api openapi
# → apps/api/openapi.json
```
