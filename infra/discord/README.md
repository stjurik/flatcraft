# @flatcraft/discord-tools

Discord community-сервер **hart.crimea.ua** як infrastructure-as-code (ADR-023).

Декларативний config (ролі, категорії, канали, permission-overwrites) живе у `config/*.ts`
як єдине джерело істини. Три idempotent-скрипти reconcile'ять його з живим сервером.

> ⚠️ Це **public community**-сервер. Окремий ops-Discord (Captain Hook monitoring,
> Phase 5C) цей tooling НЕ зачіпає — інший guild, інший бот.

## Quick start

```bash
# 0. Передумови (один раз, вручну): MANUAL_SETUP.md — створення app/bot/server.

# 1. Env (НЕ комітиться):
cp .env.example .env   # → вписати DISCORD_BOT_TOKEN і DISCORD_GUILD_ID

# 2. Snapshot (read-only): live state → docs/discord-config/{snapshot.json, README.md}
pnpm discord:snapshot

# 3. Diff (read-only): що apply збирається змінити
pnpm discord:diff

# 4. Apply (write!): створює/оновлює ролі-категорії-канали. НІКОЛИ не видаляє.
pnpm discord:apply
```

Команди доступні і напряму: `pnpm --filter @flatcraft/discord-tools snapshot|diff|apply`.

## Env vars

| Var                 | Що це                                                  |
| ------------------- | ------------------------------------------------------ |
| `DISCORD_BOT_TOKEN` | Bot token з Developer Portal (MANUAL_SETUP.md, крок 1) |
| `DISCORD_GUILD_ID`  | ID сервера hart.crimea.ua (MANUAL_SETUP.md, крок 2)    |

## Як це працює

- `config/` — декларативна модель: `roles.ts` (3-axis таксономія: authority / selfid / interest),
  `categories.ts`, `channels.ts` (з permission-overwrites), `server.ts`. Zod-валідація у `config/types.ts`.
- `lib/` — pure-функції: `diff.ts` (config vs live → DiffOp[]), `permissions.ts`
  (flag-імена ↔ bitfield), `markdown.ts` (snapshot → людиночитний doc). Тестуються без discord.js-моків.
- `scripts/` — I/O-обгортки: `snapshot.ts` (read-only), `diff.ts` (dry-run), `apply.ts` (reconcile).

**Інваріанти:**

1. `apply` ніколи не видаляє — orphan'и (є у Discord, нема у config) лише warning'аться.
2. `apply` запускається тільки вручну з машини. У CI — лише `snapshot` (weekly drift detection,
   `.github/workflows/discord-snapshot.yml`).
3. Зміни конфігурації — через PR: правите `config/*.ts` → `pnpm discord:diff` локально → merge → `pnpm discord:apply`.

## Тести

```bash
pnpm --filter @flatcraft/discord-tools test
```

Pure diff/permissions/markdown + Zod-валідація канонічного config'у + property-тести
(fast-check, idempotence). Без живого Discord.
