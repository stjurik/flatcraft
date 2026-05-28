#!/bin/sh
# Entrypoint api-образу: застосувати міграції + seed ДО старту сервера.
# Чому тут, а не окремим job'ом: один образ, self-healing на кожен boot,
# і це відповідає наміру, задокументованому в packages/db/src/migrate.ts.
# Seed ідемпотентний (onConflictDoNothing / onConflictDoUpdate) — повторний
# запуск на кожен restart безпечний. Помилка migrate/seed → set -e → контейнер
# падає (healthcheck не пройде) — fail loud, а не з напівпорожньою БД.
set -e

echo "[entrypoint] migrate + seed..."
node node_modules/@flatcraft/db/dist/init-prod.js

echo "[entrypoint] starting api: $*"
exec "$@"
