# Верифікація agy тест-інженер пасу (Run 7 Master Registry Track, Етап 1)

> Verify-then-write: кожен з 10 кейсів `testcases-registry.md` перевірено вручну
> проти реального коду валідаторів (`packages/cad-engine/src/validators/*`,
> `workers/cad/flatcraft_cad/validate/*`), не проти намірів agy.

## Підсумок

| #   | Вердикт                                                | Причина                                                                                                                                                                                                                   |
| --- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | ✅ Коректний, вже покритий                             | `bend.property.test.ts` (1000 ітерацій, той самий oracle з YAML)                                                                                                                                                          |
| 2   | ✅ Коректний, вже покритий                             | те саме                                                                                                                                                                                                                   |
| 3   | ✅ Коректний, вже покритий                             | те саме                                                                                                                                                                                                                   |
| 4   | ✅ Коректний, вже покритий                             | `profile.test.ts:177-185` (`rib_height ≤ t+r → FLANGE_TOO_SHORT`)                                                                                                                                                         |
| 5   | ✅ Коректний, вже покритий                             | `bend.property.test.ts` (boundary bendLength==max — inclusive `>` у коді)                                                                                                                                                 |
| 6   | ⚠️ **ЗНАХІДКА** — див. нижче                           | `validateHoles` існує, але НІДЕ не викликається                                                                                                                                                                           |
| 7   | ❌ Відхилено — немає валідатора                        | edge-overflow для довільних `holes[]` НЕ моделюється клієнтськи (навмисно, `holes.ts:8-9`) — це робить CadQuery `isValid` на сервері (Python, per-template, Етап 2)                                                       |
| 8   | ✅ Коректний, вже покритий                             | `bend.property.test.ts`                                                                                                                                                                                                   |
| 9   | ❌ Відхилено як заявлено, **⚠️ ЗНАХІДКА** — див. нижче | `validatePerforation` НЕ перевіряє `margin_mm` проти `length_mm`/`width_mm` — agy вигадав правило, якого нема; для заданого input (`pitch=50 > hole_size=10`) реальний валідатор повертає `[]` (валідно), а не відхилення |
| 10  | ✅ Коректний, вже покритий                             | `perforation.test.ts:88` (`обидва кроки менші за діаметр → дві HOLES_OVERLAP`); TBD-код підтверджено = `HOLES_OVERLAP`                                                                                                    |

**Жодного нового тесту в conformance-suite НЕ додано.** Усі 7 «коректних» кейсів
(1,2,3,4,5,8,10) дублюють простір, який вже вичерпно покривають існуючі
property-based тести (`bend.property.test.ts` — 1000 ітерацій по кожній
реальній комбінації товщина×радіус з YAML; `profile.test.ts`/`profile.property.test.ts`;
`perforation.test.ts`) — додавання їх окремими точковими тестами було б чистим
дублюванням без нової гарантії (CLAUDE.md §2 «без розумних абстракцій без
потреби» застосовується і до тестів: три однакові рядки кращі за передчасну
абстракцію, але зайвий дубльований тест — просто зайвий тест).

## ⚠️ Знахідка 1 (з кейсу #6): `validateHoles` — мертвий код, 0% покриття запитів

`packages/cad-engine/src/validators/holes.ts` реалізує формулу
`hole_to_bend_distance` з `bend-machine-esi.yaml` (обов'язкова CAD-перевірка,
CLAUDE.md §7 п.6 «Напрям згину» — суміжна з п. про геометричні обмеження) і
**поводиться коректно як pure-функція** (перевірено: для матеріалу
`hot_rolled_steel` (коеф. 2.5), `thickness_mm=10`, `bend_radius_mm=5`,
`distance_from_bend_mm=5` → `minDistance = 2.5×10+5 = 30` → `5 < 30` →
`holes.too_close_to_bend`).

**АЛЕ:** `grep -rn "validateHoles\b"` по `apps/` і `packages/` (окрім самого
модуля/тестів/index.ts) — **нуль викликів**. На відміну від `validateBend`/
`validateProfile`/`validatePerforation`, немає `validateExportHoles` у
`export-gate.ts`. Немає `holes.py` у `workers/cad/flatcraft_cad/validate/`
(лише `bend.py`, `perforation.py`, `profile.py`). Отже: **l_bracket `holes[]`
з `distance_from_bend_mm` замалим для товщини+радіуса приймається сьогодні
і клієнтом, і Fastify-gate, і Python-воркером** — жоден шар не блокує це до
CAD-генерації. Це не пов'язано з Registry-міграцією (пре-існуючий стан,
відкритий випадково через adversarial-тестування) — інваріант CLAUDE.md §7 п.2
(«отвори» не в переліку явно, але `hole_to_bend_distance` — задокументована
частина bend-machine spec, яку варто enforced).

**Рекомендація:** окремий issue поза цим PR — підключити `validateHoles` до
`validateExportBends`-подібного шляху (client render-gate + Fastify-gate +
`workers/cad` parity) для `l_bracket`/`corner_angle`. Виправлення НЕ входить у
scope Registry-track Етапу 1 (registry-скафолдинг, нуль змін поведінки) —
рішення yurii, чи робити це до чи після Registry-міграції.

## ⚠️ Знахідка 2 (з кейсу #9): `validatePerforation` не перевіряє `margin_mm` проти розмірів панелі

Кейс #9, ЯК ЗАЯВЛЕНО agy, невірний (`validatePerforation` перевіряє лише
`pitch <= hole_size`, повертає `[]` для наведеного input — agy вигадав
неіснуюче правило). Але сама ідея ризику — реальна: `margin_mm` (Zod-діапазон
5–100) ніде не звіряється з `length_mm`/`width_mm` (100–3000). При
`margin_mm=60` і `length_mm=100` внутрішній простір сітки
(`length_mm - 2×margin_mm = -20`) від'ємний — вироджена/неможлива сітка, яку
сьогодні НЕ ловить ані `validatePerforation` (TS/Python), ані Zod. Чи ловить
це CadQuery `isValid` на сервері — невідомо без побудови геометрії
(поза scope цієї перевірки).

**Рекомендація:** та сама — окремий issue, рішення yurii. Можливо, природне
місце для цієї перевірки — новий `def.validators` запис під час Registry-міграції
`perforated_panel` (Етап 2, перший PR) — там уже буде конкретна geometрична
модель, під яку легше писати правило й тест.

## Кейс #7 — не знахідка, підтверджена межа контракту

`holes.ts:8-9` явно документує: діаметр/накладання/геометричні колізії
(включно з виходом отвору за край) — відповідальність CadQuery `isValid` на
сервері, не client-side валідатора. Кейс #7 підтверджує цю межу, не порушує її.

## `agy-conformance-gaps.md` — оцінка

Список прогалин від agy (п. «CLAUDE.md §7») коректний за формою, але
неточний по суті в одному місці: пункт «Мінімальна полиця після гиба... не
перевіряється» — НЕ так для l_bracket/z_bracket/wall_shelf/perforated_panel
(усі покриті `profile.test.ts`+`profile.property.test.ts`+`bend.property.test.ts`
через `min_flange_mm`). Це підтверджує цінність verify-then-write: agy оцінював
«чи є явний registry-тест на це», а не «чи є ЯКИЙСЬ тест на це» — два різні
питання.
