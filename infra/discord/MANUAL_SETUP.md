# MANUAL_SETUP — ручні кроки для запуску Discord IaC

Discord API не дозволяє автоматизувати створення application/bot/сервера,
Community-фічу (ToS-wizard), Onboarding і Welcome Screen. Ці кроки робляться
руками **один раз** — далі все через `config/*.ts` + скрипти (ADR-023).

> ⚠️ Це для **нового public community-сервера** `hart.crimea.ua`.
> Ops-Discord (Captain Hook monitoring) не чіпаємо — там інший guild і бот.

## Передумови (один раз)

### 1. Створити Discord application (5 хв)

- Відкрити <https://discord.com/developers/applications> → **New Application** → Name: `hart-iac` → Create.
- Лівий sidebar → **Bot**.
- **Token**: Reset Token → скопіювати → зберегти у password manager. Він же піде у GH Secrets (`DISCORD_BOT_TOKEN`, крок 7).
- Privileged Gateway Intents: **нічого не вмикати**. Скрипти використовують лише
  базовий `Guilds` intent — Server Members Intent не потрібен (ролі/канали/overwrites
  читаються без нього; якщо колись знадобиться список учасників — увімкнете тоді).

### 2. Створити community-сервер (15 хв)

- Discord → «+» → **Create My Own** → For a club or community.
- Name: `hart.crimea.ua`.
- Server Settings → Overview → Server icon: завантажити PNG (тимчасово можна emoji).
- Server Settings → **Enable Community** → пройти wizard (accept ToS, обов'язковий
  rules-канал, verified-email requirement). **Без цього `apply` відмовиться
  створювати Announcement/Forum-канали** (preflight-перевірка підкаже).
- Скопіювати Server ID: User Settings → Advanced → **Developer Mode ON** →
  ПКМ на іконку сервера → **Copy Server ID**. Це `DISCORD_GUILD_ID`.

### 3. Запросити бот у сервер (5 хв)

- Developer Portal → ваш application → **OAuth2 → URL Generator**.
- Scopes: ✓ `bot`.
- Bot Permissions: ✓ **Administrator** (на час первинного setup — звузите у кроці 7).
- Скопіювати згенерований URL → відкрити у браузері → вибрати `hart.crimea.ua` → Authorize.
- У сервері з'явиться бот з managed-ролю `hart-iac` — це нормально
  (snapshot/diff її ігнорують).
- **Важливо:** перетягніть роль `hart-iac` на САМИЙ ВЕРХ списку ролей
  (Server Settings → Roles). Бот не може керувати ролями вище за власну.

### 4. Заповнити .env (1 хв)

У `infra/discord/.env` (НЕ комітиться — у .gitignore):

```
DISCORD_BOT_TOKEN=<token з кроку 1>
DISCORD_GUILD_ID=<server ID з кроку 2>
```

Шаблон: `cp infra/discord/.env.example infra/discord/.env`.

### 5. Перший snapshot (1 хв)

```bash
pnpm discord:snapshot
```

- Має створити `docs/discord-config/snapshot.json` + `docs/discord-config/README.md`.
- Відкрити markdown — переконатись, що читається (поки там лише @everyone,
  роль бота і дефолтні канали Discord).

### 6. Перший diff + apply (5 хв)

```bash
pnpm discord:diff
```

Очікувано: **12 create role + 7 create category + 19 create channel** і кілька
orphan-попереджень на дефолтні канали Discord (#general тощо) — це нормально,
apply їх НЕ видалить.

Якщо вивід виглядає правильно:

```bash
pnpm discord:apply
```

Перевірити у Discord UI: ролі з кольорами, категорії з каналами, gated-категорії
(ТЕХ-ПІДТРИМКА/ВИРОБНИЦТВО/НАВЧАННЯ) НЕ видимі акаунту без interest-ролі.
Дефолтні канали Discord, які не потрібні, — видалити руками.

Повторний `pnpm discord:diff` має показати «немає drift» (плюс ті ж orphan'и,
якщо ви їх лишили).

### 7. Manual-only кроки після apply

Discord API це НЕ дозволяє автоматизувати — лише руками:

- **Onboarding** (Server Settings → Onboarding): wizard на питання з опціями,
  кожна опція видає роль. Конкретний мапінг опцій → ролей: `docs/discord-config/ONBOARDING.md`.
- **Welcome Screen** (Server Settings → Welcome Screen): опис сервера + 3–5
  рекомендованих каналів (#правила, #welcome, #загальний-чат, #показуй-проєкти).
- **Server Template** (Server Settings → Server Template → Create): після apply
  збережіть URL у `docs/discord-config/TEMPLATE_URL.txt` як backup.
- **GH Secrets** для weekly snapshot: repo Settings → Secrets and variables →
  Actions → `DISCORD_BOT_TOKEN`, `DISCORD_GUILD_ID`. Після цього перевірте
  Action вручну: Actions → «Discord snapshot» → Run workflow.
- **Звуження bot-permissions**: Developer Portal → OAuth2 → URL Generator →
  згенерувати URL з `Manage Roles` + `Manage Channels` (без Administrator) →
  re-authorize. Потім у Server Settings → Roles → `hart-iac` зняти Administrator,
  лишити Manage Roles + Manage Channels (роль лишається зверху списку!).

### 8. Регулярна робота

- Зміни структури — **через PR**: правите `infra/discord/config/*.ts` →
  `pnpm discord:diff` локально → PR → merge → `pnpm discord:apply` з машини.
- `apply` ніколи не запускається у CI і ніколи нічого не видаляє: orphan'и
  (створене руками у Discord) лише попереджаються.
- Раз на тиждень GH Action робить snapshot: manual-зміни у Discord стануть
  видимі як commit-diff у `docs/discord-config/`.
