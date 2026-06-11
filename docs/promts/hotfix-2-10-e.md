[Hotfix 2.10.e — validator-bypass у експорт-pipeline + напрям згину]
АВТОНОМНИЙ РЕЖИМ: виконуй послідовно без запитів про "OK", самоверифікуйся
між фазами через тести. Зупиняйся й питай ТІЛЬКИ якщо діагноз root cause
суперечить усім 5 початковим гіпотезам або якщо тести не зеленіють після
3 ітерацій фіксу.

КОНТЕКСТ
Прочитай у такому порядку:

1. CLAUDE.md §7 (CAD-обмеження — інваріант 2 порушено), §13 (поточний стан)
2. AGENTS.md (карта workspace)
3. docs/03_DECISIONS.md — ADR-002, ADR-013, ADR-016, ADR-017, ADR-018
4. docs/04_RISKS.md — R-01, R-02 (вже актуальний, не чіпай)
5. docs/06_API_CONTRACT.md — POST /v1/exports + format помилок
6. docs/07_BEND_MACHINE_SPEC.md
7. packages/cad-engine/data/bend-machine-esi.yaml — матриця
8. packages/cad-engine/src/validators/ — TS валідатори
9. workers/cad/flatcraft_cad/ — Python pipeline (server.py, validate/ якщо є)
10. apps/api/src/routes/exports\*.ts — Fastify export route
11. packages/types/src/templates/ — Zod-схеми 5 шаблонів

BAGА (P0)
Користувач згенерував Z-bracket з thickness=5.0мм + bend_radius=2.5мм.
За matrix у bend-machine-esi.yaml для t=5 допустимі R∈{4.0, 5.0}. Валідатор
НЕ заблокував, PDF згенерувався, лежить у R2. Порушено інваріант CLAUDE.md §7 п.2
"Радіус гиба ≥ мін. для (матеріал, товщина)" — це безпекова гарантія платформи.

ОКРЕМО (P0): жоден шаблон не має поля напряму згину (UP/DOWN). Стандарт
виробничих креслень вимагає це обов'язково. Без напряму виробник може отримати
дзеркальну деталь. Дефолт за рішенням замовника: 'down' для всіх шаблонів.

МЕТА
Відновити інваріант безпеки (валідатор-парітет TS+Python з property-based тестами)
і додати напрям згину у модель + PDF + DXF. Жодного рефакторингу архітектури,
жодного UI/UX, жодної 3D-ізометрії.

КОНСТРЕЙНТИ

- НЕ переписуй PDF-генератор повністю; правки точкові (bend-table колонка +
  callout-arrow + overlapping-fix).
- НЕ міняй вже-зелені тести з Phase 2.10.d, 2.12.a, 2.14.a/b — їх багато
  (приблизно 137 pytest + 34 db + 27/71 e2e). Інваріант: ВСІ існуючі тести
  лишаються зеленими після твоїх змін.
- НЕ запускай release.yml / deploy-staging.yml — це auto-deploy на staging
  при merge у main (рішення Phase 5G). PR відкривай, мерджити буде yurii.
- НЕ чіпай R-02 у RISKS — він уже актуальний (Phase 2.14.a/b mitigation).
- Conventional Commits. Гілка: hotfix/2-10-e-validator-and-bend-direction.

ЕТАПИ (виконуй автономно)

═══════════════════════════════════════════════════════════════
A. ДІАГНОСТИКА — failing tests на обох мовах
═══════════════════════════════════════════════════════════════
A1. Створи feature branch.

A2. Запиши 5 гіпотез root cause у файл /tmp/hotfix-2-10-e-diagnosis.md
(для своєї же звітності — гіпотези допоможуть швидко локалізувати):
H1: TS-валідатор не виконується серверно у Fastify-routes
H2: Python-сторона взагалі не має валідатора
H3: YAML-парсер дає thickness як int замість float (втрата 2.5 → лookup miss)
H4: Validator існує, але викликається ПІСЛЯ генерації артефакта (race)
H5: ExportRequest минає валідатор через discriminatedUnion edge-case

A3. Failing-test #1 у packages/cad-engine/src/validators/bend.test.ts:
it("rejects t=5mm + R=2.5mm for z_bracket", () => {
const result = validateBend({ thickness_mm: 5, radius_mm: 2.5, material_code: 'cold_rolled_steel' });
expect(result).toContainEqual(expect.objectContaining({ code: 'RADIUS_NOT_ALLOWED' }));
});

A4. Failing-test #2 у workers/cad/tests/test_validator.py:
def test_export_z_bracket_t5_r2_5_must_fail(client):
resp = client.post("/export", json={
"template_slug": "z_bracket",
"thickness_mm": 5.0,
"parameters": {"bend_radius_mm": 2.5, ...}, # решта валідних
...
})
assert resp.status_code == 422
assert "RADIUS_NOT_ALLOWED" in resp.text

A5. Failing-test #3 (integration) у apps/api/tests/exports.int.test.ts:
POST /v1/exports з тими ж параметрами → 422 з RFC 9457 errors[].code='RADIUS_NOT_ALLOWED'.
Жоден файл у R2/mock-store не зʼявляється.

A6. Прогони: pnpm --filter @flatcraft/cad-engine test, cd workers/cad && uv run pytest,
pnpm --filter @flatcraft/api test:int. Який стає зеленим — там валідатор НЕ
блокує (це root cause локація). Який червоніє — там очікувана поведінка вже є,
але обходиться вище за стеком.

A7. Закомить failing tests:
git commit -m "test: failing tests for radius validation bypass (Hotfix 2.10.e A)"

A8. Запиши у /tmp/hotfix-2-10-e-diagnosis.md фактичний root cause і яка з 5 гіпотез
підтвердилась. Це піде у PR description.

═══════════════════════════════════════════════════════════════
B. ФІКС ВАЛІДАТОРА — обидва боки
═══════════════════════════════════════════════════════════════
B1. TS-сторона (packages/cad-engine/src/validators/bend.ts): - Перевір що matrix-lookup для (material_code, thickness, radius) виконується суворо. - Помилка format: { code: "RADIUS_NOT_ALLOWED", allowed: number[], got: number, thickness: number, material: string } - Failing-test #1 → зелений.

B2. Server-side gate у apps/api/src/routes/exports.ts (або як зараз називається):
ПЕРЕД forward у Python-worker → cad-engine validator виклик. Якщо є помилки → 422
з RFC 9457 problem details (приклад у docs/06_API_CONTRACT.md §0).
Якщо gate уже є — root cause був тут, фікс по факту.
Failing-test #3 → зелений.

B3. Python parity validator у workers/cad/flatcraft_cad/validate/: - Створи новий модуль (або розшир існуючий), що читає той самий
bend-machine-esi.yaml (шлях: data/bend-machine-esi.yaml усередині контейнера,
або relative з packages/cad-engine/data/ у dev). - Викликається на старті server.py export-handler ДО будь-якої CAD-операції. - Помилка → fastapi HTTPException(status_code=422, detail=[...]). - Failing-test #2 → зелений.

B4. Закомить: git commit -m "fix(cad): радіус/товщина матриця парітетно у TS+Python (Hotfix 2.10.e B)"

SELF-VERIFY: усі три failing-tests тепер зелені. Якщо ні — 3 ітерації фіксу
максимум, потім стоп і питай.

═══════════════════════════════════════════════════════════════
C. PROPERTY-BASED TESTS — закриваємо клас багів
═══════════════════════════════════════════════════════════════
C1. У packages/cad-engine додай fast-check (devDep):
pnpm --filter @flatcraft/cad-engine add -D fast-check

C2. Тест property: для будь-яких (material, thickness, radius), де matrix явно
дозволяє — validateBend повертає []; де явно забороняє — масив з ≥1 помилкою;
невідома комбінація — масив з ≥1 помилкою. 1000 iterations.

C3. У workers/cad додай hypothesis (devDep):
cd workers/cad && uv add --dev hypothesis

C4. Той самий property з боку Python. Обидва тести читають один і той же YAML.

C5. Закомить: test: property-based tests TS+Python для matrix-парітету

═══════════════════════════════════════════════════════════════
D. НАПРЯМ ЗГИНУ (UP/DOWN)
═══════════════════════════════════════════════════════════════
D1. Zod-схеми (packages/types/src/templates/): - l_bracket: top-level `bend_direction: z.enum(['up','down']).default('down')` - z_bracket: `bends: z.array(z.object({ direction: z.enum(['up','down']).default('down') })).length(2)` - corner_angle: `bend_direction: z.enum(['up','down']).default('down')` - wall_shelf: `bends: z.array(z.object({ direction: z.enum(['up','down']).default('down') }))` (1 або 2) - perforated_panel: НЕ зачіпаємо. - Unit-тести: дефолт = down, валідний override = up, інше = reject.

D2. Pydantic (workers/cad/flatcraft_cad/templates/): дзеркально + дефолти.

D3. PDF (workers/cad/flatcraft_cad/export/pdf.py): - `_draw_z_bracket_bend_table`, `_draw_l_bracket_bend_table`: додай колонку
«Напрям» з ↓ або ↑ (Helvetica Unicode підтримує). - `_draw_unfold_generic`: callout-format змінити з `BEND @ {distance}` на
`Гиб #{n} {arrow} R{radius} d={distance}мм`, де arrow = ↓ або ↑. - Overlapping-fix: якщо два callouts ближче за 30мм по X — другий зсувається
на +12pt по Y.

D4. DXF (workers/cad/flatcraft_cad/export/dxf.py): - BEND_TEXT entity format: `BEND #{n} R{radius} {DOWN|UP}` (ASCII fallback,
бо ↓/↑ Unicode не гарантовано у всіх DXF-в'юверах. Тестуй з LibreCAD
якщо встановлений; інакше snapshot-test проти eтальоного string).

D5. Сnapshot-тести оновити (deterministic by Phase 2.10.a): - Якщо snapshot-байти змінились — це очікувано, перегенеруй з pytest --snapshot-update
і закомить разом з кодом.

D6. Закомить: feat(cad): напрям згину у моделі + PDF/DXF (Hotfix 2.10.e D)

═══════════════════════════════════════════════════════════════
E. ДОКУМЕНТАЦІЯ
═══════════════════════════════════════════════════════════════
E1. docs/04_RISKS.md: додай R-12 (наступний вільний — R-11 уже single-server):
R-12. Validator-bypass у export pipeline → можливий експорт неможливих
деталей. Опис: що сталось, який інваріант порушено, який саме fix.
Mitigation: парітетний валідатор TS+Python + property-based 1000 iterations + integration-test API → 422 без створення артефактів.

E2. docs/03_DECISIONS.md: новий ADR-019:
«Server-side validation як інваріант export-pipeline».
Контекст: клієнтська валідація — лише для UX (підсвічення полів). Серверна
обов'язкова на двох рівнях: Fastify gate (перед forward у worker) і Python
parity (на старті handle_export).
Тригер перегляду: коли експорт стане BullMQ-distributed (Phase 5+ planned) —
валідатор має жити у API, не у воркері (інакше invalid jobs їдять quota).
Альтернативи: тільки клієнт (зашлях для P0-багу, відхилено), тільки worker
(worker не має contextу про quota, бажано failing fast у API).

E3. docs/05_DATA_MODEL.md: оновити L/Z/corner/wall-shelf parameters schema
приклади з полем напряму.

E4. docs/06_API_CONTRACT.md §0 Errors: приклад validation помилки оновити —
додай RADIUS_NOT_ALLOWED у перелік error codes з payload-полями allowed/got.

E5. docs/07_BEND_MACHINE_SPEC.md: додай абзац у §"Перевірки" — інваріант "напрям
згину обов'язковий атрибут кожного гибу" + посилання на ADR-019.

E6. CLAUDE.md §7: додай 6-й пункт у список перевірок — «Напрям згину (UP/DOWN)
задано для кожного гибу — рендериться на креслі стрілкою у bend-table і
поряд з callout на розгортці.»

E7. CLAUDE.md §13: додай рядок «Hotfix 2.10.e завершено (YYYY-MM-DD з date +%Y-%m-%d):
парітетний валідатор TS+Python через bend-machine-esi.yaml, property-based
1000 iter обома боками, напрям згину 'down' дефолт у 4/5 шаблонах (perfo панель
без гибів), PDF/DXF рендеряться зі стрілкою + bend-table колонкою + 30мм-overlap
fix у callouts. ADR-019, R-12. Усі N existing tests зелені (вкажи реальну
цифру з pnpm test + uv run pytest).»

E8. docs/02_ROADMAP.md: позначити Hotfix 2.10.e як done з посиланням на PR.

E9. Закомить: docs: ADR-019 + R-12 + CLAUDE/ROADMAP/data-model оновлено

═══════════════════════════════════════════════════════════════
F. PR + ЗВІТ
═══════════════════════════════════════════════════════════════
F1. Push: git push origin hotfix/2-10-e-validator-and-bend-direction

F2. gh pr create --base main --head hotfix/2-10-e-validator-and-bend-direction \
 --title "hotfix(2.10.e): validator parity + bend direction" \
 --body-file /tmp/hotfix-2-10-e-pr-body.md

F3. PR body має містити: - "## Що сталось" — короткий опис багу (з реальними параметрами Z-bracket). - "## Root cause" — яка з 5 гіпотез підтвердилась (з /tmp/hotfix-2-10-e-diagnosis.md). - "## Що змінилось" — bullet-list по етапах A-E з посиланнями на коміти. - "## Тестова перевірка" — числа: total tests до vs після, нові 3 failing→зелені,
property-based 1000 iter обома боками, snapshot updates. - "## Документація" — список оновлених doc-файлів. - "## Що НЕ робимо тут" — Phase 2.9.b (PDF polish окремо), Phase 5.10 (ізометрія
окремо), audit R2 на історичні invalid exports (окремий runbook). - "## Безпекова нота" — staging авто-deploy на merge (Phase 5G). Після мерджу
потрібно: викликати /v1/exports з invalid payload вручну → переконатись 422
на проді. Якщо щось не так — rollback через release.yml на попередній sha.

F4. Зведений підсумок у консоль: - діагноз (1 рядок) - кількість failing→зелених тестів - кількість нових unit + integration + property тестів - кількість оновлених docs - PR URL

ЗАВЕРШЕННЯ
Якщо всі етапи пройшли — robot завершив свою частину. yurii ревʼюрить PR і
мерджить (staging auto-deploys через release.yml→deploy-staging.yml).

Якщо застряг — стоп, виведи у консоль:

- на якому етапі застряг
- який тест червоніє
- 3 спроби фіксу, які пробував
- чи треба зміни поза скоупом hotfix
