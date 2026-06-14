[Phase 2.9.b — PDF/DXF drawing polish: bend numbers on lines, finished dimensions, BOM локалізація, auto-layout, hole dimensions]

КОНТЕКСТ

- ОБОВ'ЯЗКОВО прочитай перед стартом: CLAUDE.md (§7 CAD-обмеження, §9 perf budget, §13 поточний стан), docs/02_ROADMAP.md (Phase 2.9.b), docs/03_DECISIONS.md (ADR-013 thin OpenCascade, ADR-019 server-side validation), docs/04_RISKS.md.
- Hotfix 2.10.e (2026-06-03) додав напрям згину (UP/DOWN), серверну валідацію і 30мм overlap-fix. Phase X.1 (2026-06-04) додав BETA-watermark і ЗСУ-CTA. ПОТОЧНИЙ стан: 151 pytest зелені, 255 TS unit, deploy live на staging.hart.crimea.ua.
- Phase 2.9.b закриває 5 залишкових пунктів з аудиту крaслення (з 8 початкових — 3 закриті Hotfix 2.10.e + post-fix):
  1. Номери гибів безпосередньо НА bend-лініях у PDF і DXF — не лише у callout збоку
  2. Габарити готового виробу (3D, після гибки) у header — поточно тільки розгортка
  3. BOM-таблиця українською: «Маса (кг)», «Площа фарбування (м²)» тощо
  4. Auto-layout для BOM-таблиці й розмірних блоків: вибирати кут аркуша з найбільшим вільним простором (щоб не перекривати геометрію розгортки)
  5. Розмірне виносне коло (Ø8) на кожному отворі — у PDF і DXF (DIMENSION entity)

МЕТА

1. Креслення відповідає виробничим стандартам ISO 7200 (як декларує CLAUDE.md §7): однозначна ідентифікація гибів на схемі, повний BOM з фіналь­ним габа­ритом, читабельний layout без накладок, callouts розмірів на отворах.
2. Локалізація UA для оператора лазерного різання в Україні.
3. Всі покращення детерміновані (Принцип №4 з CLAUDE.md): фіксований вхід → фіксований PDF/DXF байт-у-байт.

ОБМЕЖЕННЯ

- НЕ роби 3D-ізометрію (це окремий Phase 5.10).
- НЕ переписуй ReportLab/ezdxf рендерер з нуля — це інкрементальні правки `_draw_*` функцій у `workers/cad/flatcraft_cad/export/pdf.py` і `dxf.py`.
- НЕ зачіпай Zod/Pydantic-схеми параметрів (геометрія не змінюється, тільки рендеринг).
- НЕ змінюй `bend-machine-esi.yaml` чи валідатори.
- НЕ ламай BETA-watermark і ЗСУ-CTA пайплайн з Phase X.1.
- НЕ змінюй UI/UX — це чисто server-side render.
- Conventional Commits, окремий PR `feat/2-9-b-drawing-polish`. Squash merge.
- TDD: pytest для всіх нових pure-функцій ПЕРШИМ, потім реалізація.

ДЕЛІВЕРАБЛИ

A. ПЛАН І АУДИТ ПОТОЧНОГО PDF/DXF (ДО КОДУ)

1.  Запусти `cd workers/cad && uv run pytest --no-cov -x` — переконайся, що 151 pytest зелені (baseline).
2.  Згенеруй sample PDF і DXF для всіх 5 шаблонів з дефолтними параметрами:
    - L-bracket (defaults: leg_a=100, leg_b=80, thickness=2, R=2.5, down)
    - Z-bracket (defaults з `Z_BRACKET_DEFAULT_PARAMETERS`)
    - corner_angle (defaults)
    - wall_shelf (defaults, з front_lip > 0)
    - perforated_panel (defaults)
3.  ОПИШИ у PR description (як baseline) куди саме треба втручатись для кожного з 5 пунктів — функції, рядки, render order.
4.  Зафіксуй snapshot тесту bytewise на ОДНОМУ шаблоні (L-bracket) як baseline ПЕРЕД будь-якими змінами — це буде свідомо «зламано» у відповідних кроках, але корисно як точка референсу для diff'у.

B. БЛОК 1 — НОМЕРИ ГИБІВ НА ЛІНІЯХ РОЗГОРТКИ

1.  **PDF** (`workers/cad/flatcraft_cad/export/pdf.py`, функція `_draw_unfold_generic`):
    - Для кожної bend-лінії додай маленький badge: коло Ø5мм + цифра 8pt у центрі — РОЗМІЩЕНО ПОСЕРЕДИНІ лінії гибу (midpoint).
    - Колір кола: світло-сірий fill `#FAFAFA` + чорна обводка 0.5мм для контрасту.
    - Шрифт цифри: Helvetica-Bold 8pt чорний.
    - НЕ видаляй існуючий callout збоку (`BEND #1 DOWN R2.5 d=`) — badge ДОДАЄТЬСЯ як друга візуальна підказка (для оператора, який дивиться лише на лінію).
    - Якщо bend-лінія коротша за 8мм — badge зміщується вище/нижче лінії з невеликою виноскою-рискою.
2.  **DXF** (`workers/cad/flatcraft_cad/export/dxf.py`, `_export_flat_dxf`):
    - На BEND_TEXT шарі додай ще один TEXT entity з самим `#1`/`#2` точно на midpoint лінії (text height = 3.5мм, ASCII fallback `#1`).
    - НЕ видаляй існуючий `BEND #1 90° DOWN R2.5` text entity — він залишається як full callout.
    - Перевір у LibreCAD / FreeCAD, що badge-text не перекривається з full-callout (якщо так — підвинь full-callout вище / нижче на 3мм).
3.  Pure-функція `place_bend_badges(bend_lines: tuple[BendLine2D, ...]) → tuple[BendBadge, ...]` у новому модулі `workers/cad/flatcraft_cad/export/layout/bend_badges.py` (TDD: 5+ unit-тестів — short line edge case, multiple bends, overlap avoidance).

C. БЛОК 2 — ГАБАРИТИ ГОТОВОГО ВИРОБУ У HEADER

1.  **Pure-функція** `compute_finished_dimensions(template_slug, params) → FinishedDimensions(x_mm, y_mm, z_mm)` у новому `workers/cad/flatcraft_cad/export/dimensions.py`:
    - L-bracket: `x = leg_a, y = leg_b, z = thickness` (плюс bend_radius урахований у layout — гнутий G-shape має габарит == max(leg_a, leg_b) у проекції XY, висота = min(leg_a, leg_b)).
    - Z-bracket: `x = flat_bottom + flat_middle*cos(90°) + flat_top, y = flat_middle*sin(90°), z = thickness` — або точніше через unfold-bbox after re-bend. Документуй формулу у docstring.
    - corner_angle: те саме що L-bracket (геометрично ідентичні).
    - wall_shelf: `x = width, y = depth_back + depth_shelf*cos(90°), z = thickness + front_lip*sin(90°)` (або як обчислюється — обери чітку конвенцію і задокументуй).
    - perforated_panel: `x = length, y = width, z = thickness` (плоска, без гибів).
    - 10+ pytest на pure-функцію (по 2 на шаблон з різними параметрами + edge cases).
2.  **PDF header** (`_draw_header` або еквівалент у pdf.py):
    - ДОДАЙ рядок «Габарити готового виробу: X × Y × Z мм» нижче рядка з матеріалом/товщиною.
    - Формат значень: округлення до 0.1мм, без trailing zeros (`100 × 80 × 2 мм`, не `100.0 × 80.0 × 2.0 мм`).
    - Шрифт: той самий що у решті header (Helvetica 10pt).
    - У PDF snapshot test перевір, що рядок присутній для ВСІХ 5 шаблонів.

D. БЛОК 3 — BOM ЛОКАЛІЗАЦІЯ UA

1.  У `compute_bom` або `_draw_bom_table` (знайди де саме рендеряться labels — переважно у pdf.py):
    - English → Ukrainian мапа:
      - "Material" → "Матеріал"
      - "Thickness" → "Товщина (мм)"
      - "Blank width" → "Ширина заготовки (мм)"
      - "Blank height" → "Висота заготовки (мм)"
      - "Cut length" → "Довжина різу (мм)"
      - "Bend count" → "Кількість гибів"
      - "Hole count" → "Кількість отворів"
      - "Paint area" → "Площа фарбування (м²)"
      - "Mass" → "Маса (кг)"
    - Якщо є значення «N/A» / «—» — лишити як є (універсальний символ).
2.  Округлення: маса → 0.01 кг, площа → 0.001 м², довжина різу → 1мм, ширина/висота → 1мм.
3.  ВРАХУЙ: у PDF може використовуватись builtin font, що НЕ підтримує кирилицю → використай **той самий Inter TTF**, що Phase 2.16.a (`apps/web/src/app/_og-fonts/Inter-*.ttf`). Закопіюй потрібні subsets у `workers/cad/flatcraft_cad/assets/fonts/` (НЕ commit'ити OFL-license duplicate без `LICENSE` у тому ж каталозі — додай OFL.txt). Або, якщо `_draw_beta_watermark` (Phase X.1) уже використовує кирилицю через `_draw_beta_watermark` — дивись, який шрифт зареєстровано, і reuse.
4.  Property test: для будь-яких 5 валідних параметрів кожного шаблону BOM-таблиця має рівно N очікуваних рядків, без англійських слів (regex `[A-Za-z]{4,}` не повинен матчити лейбли — фон/числа можуть мати, лейбли — ні).

E. БЛОК 4 — AUTO-LAYOUT ANNOTATION CORNER

1.  **Pure-функція** `pick_annotation_corner(geometry_bbox: BBox2D, page_bbox: BBox2D, annotation_size: Size2D, margin_mm: float = 10) → Corner` у новому `workers/cad/flatcraft_cad/export/layout/corner_picker.py`:
    - 4 кандидати: TL, TR, BL, BR.
    - Для кожного кандидата обчисли вільний прямокутник між геометрією і краєм аркуша.
    - Поверни той, де вільний прямокутник ≥ annotation_size з найбільшим запасом.
    - Якщо НІ ОДИН не вміщується → повертай `Corner.BR` (поточний default) + помітка для fallback на другий аркуш (фактично другий аркуш — окремий Phase, наразі fallback = просто рендер у BR з overflow і issue-логом).
    - 8+ pytest: усі 4 кутових сценарії + дегенеративний (геометрія заповнює весь аркуш) + аркуш менший за annotation (raises).
2.  **PDF**: і `_draw_bom_table`, і `_draw_dimensions_block` (якщо є окремий) — отримують `corner: Corner` параметр і рендерять там.
3.  **Visual smoke test**: вручну згенеруй PDF для L-bracket з тонким (leg_a=300, leg_b=20) і товстим (leg_a=80, leg_b=80) — переконайся, що для першого BOM на BR (вільно), для другого — на TR (бо BR забитий геометрією). Зафіксуй PDF візуально як screenshot у `docs/screenshots/phase-2-9-b-layout-{slim,blocky}.png` (опційно — для ревью).

F. БЛОК 5 — HOLE DIMENSIONS (Ø)

1.  **PDF** (`_draw_unfold_generic`, де рендеряться holes circles):
    - Для кожного отвору додай dim-callout: маленька лінія-виноска від кола (зовнішня дотична) + текст `Ø8` поряд (Helvetica 7pt).
    - Якщо отворів багато (perforated_panel — сотні): рендерити dim ТІЛЬКИ для першого у grid + текстова анотація «×N отворів» (де N — total count). Pure helper `should_dim_individual_holes(count) → bool` (cap = 10).
    - Якщо отвори різного діаметра (наразі немає такого шаблону, але майбутньо) → dim'ити кожен унікальний діаметр окремо.
2.  **DXF** (`_export_flat_dxf`):
    - Додай DIAMETRIC DIMENSION entities на новому шарі DIM_HOLES (red, lineweight 0.18мм).
    - Використай `ezdxf.add_diametric_dim(layout, center=(cx, cy), radius=r, ...)`.
    - Aналогічно: cap = 10 для perfo-панелі, інакше DXF файл стане надто важким.
3.  5+ pytest на pure-helper + integration test «dim entities у DXF on layer DIM_HOLES».

G. PERFORMANCE BUDGET

- Перевір CLAUDE.md §9: «Експорт PDF простого виробу < 5с». Після всіх 5 блоків — заміряй `time uv run python -m flatcraft_cad.cli export l_bracket --output /tmp/test.pdf` 5 разів, median має бути < 5с (наразі ~1с).
- Якщо вилазиш за бюджет — задокументуй у `docs/04_RISKS.md` як R-13 «PDF generation overhead» і чи планується оптимізація.

H. ТЕСТИ

- Усі нові pure-функції: 8+ pytest кожна, edge cases покриті.
- Snapshot тести для PDF (text-extract — НЕ bytewise, бо ReportLab timestamps): для кожного шаблону перевір, що:
  - Header містить «Габарити готового виробу:» і має «×» symbol з трьома числами.
  - BOM містить «Маса (кг)» і «Площа фарбування (м²)» (UA labels).
  - Bend section містить badge для кожного гибу (parse via pdftotext).
  - Hole dim section містить «Ø» для ВСІХ holes у L/corner/wall_shelf і ОДИН «Ø ×N» для perfo.
- Existing 151 pytest залишаються зеленими.
- Existing 27 Playwright e2e залишаються зеленими (UI/UX не змінюємо).
- 5+ нових integration тестів для API forward (POST /v1/exports → отримуємо PDF з усіма блоками).

I. ДОКУМЕНТАЦІЯ

1.  `docs/03_DECISIONS.md` — ADR-021 «Drawing polish: auto-layout corner picker + UA-локалізація BOM» (короткий — 1 сторінка, контекст + рішення + наслідки).
2.  `docs/04_RISKS.md` — якщо потрібно, R-13 «PDF generation perf overhead» (тільки якщо вилазимо за бюджет; інакше пропускай).
3.  CLAUDE.md §13 — рядок «Phase 2.9.b завершено (YYYY-MM-DD): bend badges на лініях розгортки (PDF+DXF), finished dimensions у header, BOM UA-локалізація через Inter TTF, auto-layout corner picker, Ø-callouts на отворах (cap 10 для perfo). N+5 pytest, M+5 integration, snapshot-тести через pdftotext. ADR-021.»
4.  `docs/06_API_CONTRACT.md` — ОПЦІОНАЛЬНО: якщо response shape `BOM` змінюється (наразі ні — лейбли тільки у PDF, не у JSON response), не зачіпай.

J. PR FORMAT

- Branch `feat/2-9-b-drawing-polish`.
- Squash-merge у `main`.
- PR description має містити:
  - Чек-лист 5 блоків (✓ для кожного).
  - Перед/після screenshots PDF для L-bracket і perforated_panel (особливо show'ить badges + BOM + corner-pick effect).
  - Список нових pure-функцій з coverage %.
  - Подяку Hotfix 2.10.e за infrastructure (30мм overlap-fix re-usable у auto-layout? — задокументуй).

ПОЧАТОК

1. Покажи ПЛАН: послідовність комітів, які файли торкнеш у кожному комі­ті, які pure-функції додаєш, де очікуєш потенційні проблеми (5 ризиків з ймовірно­стями).
2. Дочекайся мого "OK".
3. Виконуй блоки A→B→C→D→E→F→G в ОКРЕМИХ комітах. Тести-першими у кожному комі­ті (TDD red-green-refactor).
4. Після кожного блоку звітуй: які тести додані, які з existing змінилися (snapshot diffs), perf номери.
5. У кінці згенеруй фінальний PR-checklist + перед/після PDF на L-bracket і perfo.
