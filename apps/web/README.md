# @flatcraft/web

Next.js frontend для flatcraft. Див. `AGENTS.md` у корені для повного опису.

## Запуск

```bash
pnpm --filter @flatcraft/web dev
```

Відкрийте http://localhost:3000.

## Перші файли, які потрібно створити (Phase 0)

```
src/app/layout.tsx           # root layout з Tailwind + Auth providers
src/app/page.tsx             # лендінг
src/app/(app)/templates/page.tsx
src/app/(app)/templates/[slug]/page.tsx
src/lib/api-client.ts
src/lib/auth.ts
src/styles/globals.css
next.config.ts
tailwind.config.ts
postcss.config.js
```
