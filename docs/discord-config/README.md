# Discord — hart.crimea.ua

> Авто-згенеровано `pnpm discord:snapshot` (infra/discord, ADR-023).
> НЕ редагувати вручну — зміни вносяться у `infra/discord/config/*.ts`.

## Ролі

| Роль | Колір | Hoist | Position | Managed | Permissions |
| --- | --- | --- | --- | --- | --- |
| hart-iac | #000000 |  | 13 | ✓ | Administrator |
| 🔴 Founder | #ed4245 | ✓ | 12 |  | Administrator |
| 🟠 Moderator | #f39c12 | ✓ | 11 |  | KickMembers, ManageMessages, ModerateMembers, MuteMembers |
| 🟢 Verified-Manufacturer | #57f287 | ✓ | 10 |  | AddReactions, AttachFiles, EmbedLinks, ReadMessageHistory, SendMessages |
| ⚪ Member | #99aab5 |  | 9 |  | AddReactions, AttachFiles, EmbedLinks, ReadMessageHistory, SendMessages |
| 💡 i-am/DIY | #3498db |  | 8 |  | — |
| 🏢 i-am/Business | #9b59b6 |  | 7 |  | — |
| 🛠️ i-am/Engineer | #1abc9c |  | 6 |  | — |
| 🏭 i-am/Manufacturer | #e67e22 |  | 5 |  | — |
| 🐛 interest/Support | #95a5a6 |  | 4 |  | — |
| 🎨 interest/Design | #95a5a6 |  | 3 |  | — |
| 🏭 interest/Production | #95a5a6 |  | 2 |  | — |
| 📚 interest/Learning | #95a5a6 |  | 1 |  | — |
| @everyone | #000000 |  | 0 |  | AddReactions, AttachFiles, ChangeNickname, Connect, CreateInstantInvite, CreatePrivateThreads, CreatePublicThreads, EmbedLinks, ReadMessageHistory, RequestToSpeak, SendMessages, SendMessagesInThreads, SendPolls, SendVoiceMessages, Speak, Stream, UseApplicationCommands, UseEmbeddedActivities, UseExternalApps, UseExternalEmojis, UseExternalSounds, UseExternalStickers, UseSoundboard, UseVAD, ViewChannel |

## Категорії та канали

### 📋 ІНФОРМАЦІЯ

| Канал | Тип | Topic | Теги |
| --- | --- | --- | --- |
| оголошення | GuildAnnouncement | Релізи, downtime, новини проєкту. | — |
| правила | GuildText | Правила спільноти UA — прочитай перед першим повідомленням. | — |
| welcome | GuildText | Вітання новим учасникам. | — |
| ресурси | GuildText | Лінки: /about, ROADMAP, GitHub. | — |

### Text Channels

_(порожньо)_

### Voice Channels

| Канал | Тип | Topic | Теги |
| --- | --- | --- | --- |
| General | GuildVoice | — | — |

### 💬 ЗАГАЛЬНЕ

| Канал | Тип | Topic | Теги |
| --- | --- | --- | --- |
| показуй-проєкти | GuildForum | — | готово, у-процесі, ідея |
| загальний-чат | GuildText | — | — |

### 🎨 ПРОЄКТУВАННЯ

| Канал | Тип | Topic | Теги |
| --- | --- | --- | --- |
| поради-з-проєктування | GuildForum | — | material:steel, material:aluminum, material:stainless, побут, меблі, виробництво |
| підготовка-креслень | GuildText | — | — |
| запит-нового-шаблону | GuildText | — | — |

### 🐛 ТЕХ-ПІДТРИМКА

| Канал | Тип | Topic | Теги |
| --- | --- | --- | --- |
| bug-report | GuildForum | — | severity:critical, severity:high, severity:medium, severity:low, status:open, status:investigating, status:fixed, tpl:l-bracket, tpl:z-bracket, tpl:corner-angle, tpl:wall-shelf, tpl:perfo-panel |
| помилки-валідації | GuildText | — | — |
| feature-request | GuildText | — | — |

### 🏭 ВИРОБНИЦТВО

| Канал | Тип | Topic | Теги |
| --- | --- | --- | --- |
| вибір-виробника | GuildText | — | — |
| виробники-офіційно | GuildText | Пишуть лише верифіковані виробники; читають усі. | — |
| k-фактор-і-допуски | GuildText | — | — |

### 📚 НАВЧАННЯ

| Канал | Тип | Topic | Теги |
| --- | --- | --- | --- |
| для-новачків | GuildText | — | — |
| туторіали | GuildText | — | — |

### 🎙️ ГОЛОСОВІ

| Канал | Тип | Topic | Теги |
| --- | --- | --- | --- |
| Voice — Загальний | GuildVoice | — | — |
| Voice — Office-hours | GuildVoice | — | — |

### (без категорії)

| Канал | Тип | Topic | Теги |
| --- | --- | --- | --- |
| лише-модератори | GuildText | — | — |
| правила | GuildText | — | — |

## Permission-overwrites

| Ціль | Роль | Allow | Deny |
| --- | --- | --- | --- |
| категорія 🐛 ТЕХ-ПІДТРИМКА | @everyone | — | ViewChannel |
| категорія 🐛 ТЕХ-ПІДТРИМКА | 🐛 interest/Support | ViewChannel | — |
| категорія 🐛 ТЕХ-ПІДТРИМКА | 🟠 Moderator | ViewChannel | — |
| категорія 🏭 ВИРОБНИЦТВО | @everyone | — | ViewChannel |
| категорія 🏭 ВИРОБНИЦТВО | 🏭 interest/Production | ViewChannel | — |
| категорія 🏭 ВИРОБНИЦТВО | 🟠 Moderator | ViewChannel | — |
| категорія 📚 НАВЧАННЯ | @everyone | — | ViewChannel |
| категорія 📚 НАВЧАННЯ | 📚 interest/Learning | ViewChannel | — |
| категорія 📚 НАВЧАННЯ | 🟠 Moderator | ViewChannel | — |
| #лише-модератори | @everyone | — | ViewChannel |
| #оголошення | @everyone | — | SendMessages |
| #оголошення | 🟠 Moderator | SendMessages | — |
| #правила | @everyone | — | SendMessages |
| #правила | @everyone | — | SendMessages |
| #правила | 🟠 Moderator | SendMessages | — |
| #bug-report | @everyone | — | ViewChannel |
| #bug-report | 🐛 interest/Support | ViewChannel | — |
| #bug-report | 🟠 Moderator | ViewChannel | — |
| #ресурси | @everyone | — | SendMessages |
| #ресурси | 🟠 Moderator | SendMessages | — |
| #помилки-валідації | @everyone | — | ViewChannel |
| #помилки-валідації | 🐛 interest/Support | ViewChannel | — |
| #помилки-валідації | 🟠 Moderator | ViewChannel | — |
| #feature-request | @everyone | — | ViewChannel |
| #feature-request | 🐛 interest/Support | ViewChannel | — |
| #feature-request | 🟠 Moderator | ViewChannel | — |
| #вибір-виробника | @everyone | — | ViewChannel |
| #вибір-виробника | 🏭 interest/Production | ViewChannel | — |
| #вибір-виробника | 🟠 Moderator | ViewChannel | — |
| #виробники-офіційно | @everyone | — | SendMessages |
| #виробники-офіційно | 🟢 Verified-Manufacturer | SendMessages | — |
| #k-фактор-і-допуски | @everyone | — | ViewChannel |
| #k-фактор-і-допуски | 🏭 interest/Production | ViewChannel | — |
| #k-фактор-і-допуски | 🟠 Moderator | ViewChannel | — |
| #для-новачків | @everyone | — | ViewChannel |
| #для-новачків | 📚 interest/Learning | ViewChannel | — |
| #для-новачків | 🟠 Moderator | ViewChannel | — |
| #туторіали | @everyone | — | SendMessages |
| #туторіали | 🟠 Moderator | SendMessages | — |
