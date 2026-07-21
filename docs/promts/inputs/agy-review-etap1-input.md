# Вхід для agy — Рев'юер (Run 7 Master Registry Track, Етап 1)

Ти — незалежний Рев'юер (окрема модель, Gemini). Оціни diff гілки
`feat/registry-core` (Етап 1: registry-скафолдинг, ADR-033) проти
docs/12-контракту та інваріантів CLAUDE.md §7 нижче.

НЕ використовуй жодних command/bash/terminal інструментів — лише `read_file`
і `write_file`.

**Крок 1:** прочитай через `read_file` весь diff:
`/home/yurii/hart/docs/promts/inputs/_review-etap1.diff`

**Крок 2:** звір його проти інваріантів нижче (§A і §B) і дай вердикт по
кожному пункту: ✅ дотримано / ⚠️ сумнівно (поясни) / ❌ порушено (поясни,
з посиланням на конкретний рядок diff).

**Крок 3:** збережи результат ЛИШЕ у файл
`/home/yurii/hart/docs/promts/inputs/review-result-etap1.md` — формат:
підсумковий вердикт (✅/⚠️/❌) зверху, потім таблиця по кожному пункту §A/§B,
потім (якщо є) розділ «Інше, що впало в очі» для зауважень поза списком.

НЕ пиши в жодні інші файли.

---

## §A. Інваріанти CLAUDE.md §7 (CAD-обмеження), які контракт НЕ сміє ламати

1. Байт-у-байт DXF/PDF — детермінізм (CLAUDE.md §2.4). У цьому PR — жодних
   змін у `to_dxf`/`to_pdf`/існуючих Python-шаблонах.
2. Render-gate (ADR-026): 3D-сцена рендериться лише при валідних параметрах;
   `R3FErrorBoundary` — backstop.
3. Серверна валідація `bend_radius` через cad-engine у Fastify + Python
   parity (ADR-019).
4. `events` — без PII.
5. Single source of truth для bend-матриці —
   `packages/cad-engine/data/bend-machine-esi.yaml`.
6. Головний entry `@flatcraft/cad-engine` browser-safe (без `node:*`);
   fs-loader — лише через subpath `/node`.

## §B. Контракт docs/12_TEMPLATE_CONTRACT.md (актуальний, ПІСЛЯ diff)

### §3 Conformance-suite (4 автогенеровані перевірки на slug)

1. Schema parity TS↔Python (property-based) — fast-check + hypothesis,
   slug-паритет `set(TS_REGISTRY.keys()) == set(PY_REGISTRY.keys())`.
2. DXF/PDF детермінізм (фіксований seed → фіксовані байти).
3. Render-gate — generic-viewport НЕ рендерить `<Canvas>` при issues.
4. e2e smoke (Playwright), автогенерований з реєстру.
5. React-free import у `apps/api` (§3.5) — `apps/api` НЕ тягне
   `react`/`react-dom` у бандл.

Suite fail-closed: новий шаблон без усіх 4-х проходжень — червоний CI.
Реєстр без conformance = червоний CI.

### §5 Інваріанти, які контракт НЕ сміє ламати (таблиця)

| Інваріант                                | Джерело        | Як контракт зберігає                                                                                     |
| ---------------------------------------- | -------------- | -------------------------------------------------------------------------------------------------------- |
| Байт-у-байт DXF/PDF                      | CLAUDE.md §2.4 | conformance §3.2 — снапшот-тести; жодних правок у `to_dxf`/`to_pdf` при міграції шаблону                 |
| Render-gate ADR-026                      | ADR-026        | generic-viewport ЗАВЖДИ виклик `validateProfile()` через `def.validators`; `R3FErrorBoundary` — backstop |
| Products ADR-027                         | ADR-027        | `def.products?: ProductDefinition[]` — те саме shape'ом (`fixed`, `userEditableFields`)                  |
| Browser-safe entry `packages/cad-engine` | CLAUDE.md §13  | `packages/templates` НЕ імпортує `node:*`; `fs`-loader — тільки через subpath `/node`                    |
| Server-side validation ADR-019           | ADR-019        | Fastify-gate викликає `def.validators` через registry ДО постановки job'а в BullMQ                       |
| React-free реєстр                        | ADR-033 §1     | conformance §3.5 — import-graph `apps/api/src/routes/exports.ts` не містить `react`/`react-dom`          |

### §6 Міграційний план — релевантний рядок для ЦЬОГО PR

> PR 2: `packages/templates` — новий пакет: `TemplateDefinition`,
> `TEMPLATE_REGISTRY` (порожній), conformance-suite (у т.ч. §3.5 react-free);
> перенесення `ShapeCommand` з `packages/ui/src/3d-viewport/geometry.ts` у
> `packages/cad-engine` (споживачі-import'и `apps/web` оновити).

### Важливий контекст для оцінки: ЦЕЙ PR ПОВИНЕН БУТИ «нуль змін поведінки»

`TEMPLATE_REGISTRY` (TS) і `TEMPLATES` (Python) — ОБИДВА порожні у цьому PR.
Жоден з 6 наявних шаблонів НЕ мігрує зараз (міграція — Етап 2, по одному
PR на шаблон). Це означає: усі новостворені conformance-тести (property-based,
render-gate, e2e stub) сьогодні виконують 0 ітерацій — це очікувано, НЕ
пропуск/помилка (перевір, що дизайн справді "0 ітерацій з порожнім реєстром",
а не "тести написані, але фактично never-виконуються через баг").

### Свідомі відхилення від початкового докс-ескізу (вже занесені у §1 docs/12, шукай "Реалізовано" callout у diff)

1. `ProfileValidator<Params>` живе у `packages/templates`, не в
   `@flatcraft/cad-engine/validators` — обґрунтування у diff-коментарі.
2. `ProductDefinition.fixed` (не `fixedParameters`).
3. `TemplateDefinition.labels: {uk, en}` — ADR-037 §5 Consequence, єдиний
   дозволений виняток зі STOP-правила "не чіпати docs/12-контракт" (окремий
   коміт з посиланням на ADR-037).

Питання до тебе: чи є ці відхилення архітектурно виправданими, чи щось з
них варто підняти як STOP для yurii?
