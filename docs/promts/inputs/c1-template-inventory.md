# C1 — Інвентаризація 6 шаблонів (вхід для ADR-033)

> **Джерело:** прочитано `packages/types/src/templates/*.ts` (6 схем), `packages/ui/src/3d-viewport/*-scene.tsx` + `geometry.ts`, `apps/web/src/components/*-{studio,editor,viewport}.tsx` + `template-studio.tsx` + `scene.tsx`, `packages/types/src/domain/export.ts`, `workers/cad/flatcraft_cad/templates/*.py` + `base.py` + `__init__.py`, `workers/cad/flatcraft_cad/{unfold,export/dxf,export/pdf,validate/profile}.py`, `apps/web/tests/e2e/`.
>
> **Правило:** нічого не вигадано. Кожна фактична деталь має file:line. `—` = недоступно / не читалося. Мета — інвентарний факт, не оцінка.

## Позначення

- ✅ — однакова структура (використовує спільну абстракцію або той самий патерн)
- ⚠️ — стилістичний дрейф (робить те саме, але іншим способом)
- ❌ — поведінковий дрейф (робить інше)

---

## 1. Матриця аспектів × 6 шаблонів

| Аспект                        | l_bracket                                                                | z_bracket              | corner_angle | wall_shelf         | enclosed_shelf                | perforated_panel                     |
| ----------------------------- | ------------------------------------------------------------------------ | ---------------------- | ------------ | ------------------ | ----------------------------- | ------------------------------------ |
| A1 Zod-схема, top-level       | ✅ scalar+holes                                                          | ✅ bends[2]            | ✅ grid      | ⚠️ bends[1-2]      | ❌ bends[3-4] + nested opts   | ❌ bends[4] + grid + shape           |
| A2 `.describe()`-групи        | ✅ 3 стандартні                                                          | ✅                     | ✅           | ✅ + summary       | ⚠️ 4 групи (нестандартна)     | ⚠️ 3, без «Гиб» окремо               |
| A3 Валідатори (Zod refine)    | ⚠️ union radii                                                           | ⚠️ union radii         | ⚠️           | ❌ +refine `lip`   | ⚠️ nested nullable            | ⚠️                                   |
| A4 Scene builder              | ✅ у `geometry.ts`                                                       | ✅ у `geometry.ts`     | ⚠️ reuse L   | ✅ у `geometry.ts` | ❌ inline у `-scene.tsx`      | ❌ inline у `-scene.tsx`             |
| A5 Editor UX (AutoForm)       | ✅ generic                                                               | ✅ generic             | ✅           | ⚠️ +custom text    | ⚠️ omits 3 полів + merge      | ❌ SegmentedControl **над** AutoForm |
| A6 Studio (`TemplateStudio`)  | ✅                                                                       | ✅                     | ✅           | ✅                 | ✅ + products                 | ⚠️ +products (visibleFields)         |
| A7 Viewport (render-gate)     | ✅ `validateProfile`                                                     | ✅                     | ✅           | ✅                 | ❌ **немає** render-gate      | ✅ (гейт не потрібен, geometry OK)   |
| A8 Python builder             | ✅ Template base                                                         | ✅                     | ✅           | ✅ +2 validators   | ⚠️ nested Pydantic            | ⚠️ +field_validator bends.length     |
| A9 Unfold dispatch            | ✅ окрема функція `unfold_*`                                             | ✅                     | ✅           | ✅                 | ⚠️ **cross-shape** (не рівна) | ⚠️ також cross-shape (bulge R5)      |
| A10 DXF dispatch              | ✅ generic exporter                                                      | ✅                     | ✅           | ✅                 | ⚠️ окремі гілки для cross     | ⚠️ culling біля отворів              |
| A11 PDF dispatch              | ✅ via `compute_finished_dimensions(template_slug, params)` (pdf.py:156) | ✅                     | ✅           | ✅                 | ✅                            | ✅                                   |
| A12 Server-validate (profile) | ✅ через `template_slug` (validate/profile.py)                           | ✅                     | ✅           | ✅                 | ✅                            | ✅                                   |
| A13 ExportRequest union       | ✅ Refined                                                               | ✅                     | ✅           | ❌ **Base**Schema  | ✅                            | ✅                                   |
| A14 e2e dedicated spec        | ❌ **немає**                                                             | ✅ `z-bracket.spec.ts` | ✅           | ✅                 | ❌ **немає** (продукт-тест)   | ✅ `perforated-panel.spec.ts`        |

---

## 2. Топ-10 копі-пасту

Впорядковано за ризиком тихого дрейфу (перше = найнебезпечніше).

| #   | Місце                                                                                                                       | Файли (по одному прикладу з рядком)                                                                                                                       | Ризик                                                                                                  |
| --- | --------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| 1   | `field_validator("bend_radius_mm")` у Python (перевірка union)                                                              | `l_bracket.py:64-71`, `z_bracket.py:45-52`, `corner_angle.py:49-56`, `wall_shelf.py:51-58`, `perforated_panel.py:67-74`, аналогічно в `enclosed_shelf.py` | ⚠️ Нова товщина/радіус → правити у 6 файлах у lock-step                                                |
| 2   | `TemplateStudioSlug` union + `SLUGS_WITH_BENDS/PROFILE/PERFORATION` set-и hardcoded                                         | `apps/web/src/components/template-studio.tsx:29-35,90-107`                                                                                                | ❌ Додавання шаблону — оновлення 4-х set-ів вручну, нема type-safety                                   |
| 3   | Editor validation chain `useMemo(schema.safeParse) + zodIssuesToFieldErrors + bendMatrixIssues + profileIssues + allErrors` | `l-bracket-editor.tsx:49-86`, `wall-shelf-editor.tsx:33-69`, `z-bracket-editor.tsx`, `corner-angle-editor.tsx`                                            | ⚠️ `perforated-panel-editor.tsx:59-62` замінює `bendMatrixIssues` на `validatePerforation` — асиметрія |
| 4   | Viewport wrapper (`Canvas + OrbitControls + dynamic ssr:false + R3FErrorBoundary + validateProfile`)                        | `*-viewport.tsx` (5 з 6, окрім `enclosed-shelf-viewport.tsx` без render-gate)                                                                             | ⚠️ Копіпаст 20-30 рядків на файл                                                                       |
| 5   | Scene compileShape → `Shape` (moveTo/lineTo/absarc/closePath) + `ExtrudeGeometry`                                           | `l-bracket-scene.tsx:21-41`, `z-bracket-scene.tsx:25-45`, `wall-shelf-scene.tsx:39-59`, `corner-angle-scene.tsx:38-109`                                   | ⚠️ Функція з `geometry.ts` міняє signature — 4 сцени падають незалежно                                 |
| 6   | Grid-holes у сценах (`linspace` × rows × cols → CylinderGeometry)                                                           | `corner-angle-scene.tsx:78-106`, `wall-shelf-scene.tsx:66-94`                                                                                             | ⚠️ Формула виправлена в одному — інший тихо продовжує старе                                            |
| 7   | AutoForm `.omit({ ... })` полів `bend_direction` / `bends` / nested                                                         | `l-bracket-editor.tsx:23`, `wall-shelf-editor.tsx:25`, `enclosed-shelf-editor.tsx:26-30`                                                                  | ⚠️ Rename поля у Zod → `omit()` тихо пропускає, нема type-error                                        |
| 8   | Python builder: XZ profile через `radiusArc + extrude`                                                                      | `l_bracket.py:74-99`, `corner_angle.py:59-83` (майже ідентична логіка, окремі функції)                                                                    | ⚠️ Профіль дуплюється; corner_angle тільки додає 3D-отвори                                             |
| 9   | Studio: `TemplateStudio` wrap + `renderEditor`+`renderViewport`                                                             | Всі 6 `*-studio.tsx`                                                                                                                                      | ⚠️ Різні iмпорти, однакова обгортка (10-20 рядків)                                                     |
| 10  | Python `__init__.py` `__all__` list                                                                                         | `workers/cad/flatcraft_cad/templates/__init__.py`                                                                                                         | ❌ `enclosed_shelf` **не експортовано** (пропущено — потенційна проблема!)                             |

---

## 3. Фактичні поведінкові розбіжності

**Кандидати в баги або в свідому варіативність, яку контракт ADR-033 має вмістити.**

### F1. `WallShelfParametersBaseSchema` у `ExportRequest` замість refined — cross-field constraint не працює на server-side парсері

- **Файл:** `packages/types/src/domain/export.ts:47` — використовує **BaseSchema** (без refine).
- **Причина:** Zod `discriminatedUnion` вимагає `ZodObject`, не `ZodEffects` (refine обгортає в Effects).
- **Наслідок:** серверний парсер `ExportRequest` пропускає `front_lip_mm === 0 || >= 5` (задано у `wall-shelf.ts:81-86`).
- **Порятунок:** Pydantic `wall_shelf.py:60-66` — enforce'ить.
- **Ризик:** UI дозволяє `front_lip=1` → серверний Zod проходить → Python валідатор кидає → **async export failure** замість inline error.

### F2. `enclosed-shelf-viewport.tsx` — немає `validateProfile` render-gate

- **Контраст:** `l/z/corner/wall-viewport.tsx` викликають `validateProfile()` перед Canvas (ADR-026).
- **Причина:** ADR-027 PR 7d — заявлено, що geometry завжди валідна при OK-схемі + rib.
- **Ризик:** якщо `rib_height > t+d`, Canvas все ще монтується; помилка вискакує лише при експорті. UX-gap — не інваріант ADR-026.

### F3. `perforated-panel-editor.tsx:59-62` замінює `bendMatrixIssues` на `validatePerforation`

- **Контраст:** усі інші editor'и мають `bendMatrixIssues(schema, params)` як компонент `allErrors`.
- **Причина:** ADR-031 — `rib_height` обов'язковий → geometry завжди валідна → matrix перевірка нібито не потрібна.
- **АЛЕ:** `perforated_panel.py:67-74` **все ще** має `field_validator("bend_radius_mm")`.
- **Ризик:** клієнт не показує bend-matrix issue → серверний Python кидає → неочікуваний 422 при експорті.

### F4. `bends` контракт **асиметричний** — то scalar, то array різних довжин

| slug             | Поле                                    | Тип / довжина                                |
| ---------------- | --------------------------------------- | -------------------------------------------- |
| l_bracket        | `bend_direction: 'up'\|'down'`          | scalar (`l-bracket.ts:41`)                   |
| z_bracket        | `bends: BendSpec[]` length **2**        | array (`z-bracket.ts:58-62`)                 |
| corner_angle     | `bend_direction: 'up'\|'down'`          | scalar (`corner-angle.ts:39`)                |
| wall_shelf       | `bends: BendSpec[]` min **1** max **2** | array (`wall-shelf.ts:56-61`)                |
| enclosed_shelf   | `bends: BendSpec[]` min **3** max **4** | array (`enclosed-shelf.ts:86-91`)            |
| perforated_panel | `bends: BendSpec[]` length **4**        | array (Pydantic `perforated_panel.py:67-80`) |

- **Ризик для ADR-033:** будь-який generic `TemplateDefinition` муситиме або уніфікувати (breaking), або тримати union type `bend_direction | bends[]`. Це головний контракт-проектний виклик.

### F5. Scene-builder розділено між **двома шарами** — `geometry.ts` і inline у `-scene.tsx`

- **`packages/ui/src/3d-viewport/geometry.ts`** експортує 3 з 6: `buildLBracketShapeCommands` (line 36), `buildZBracketShapeCommands` (line 97), `buildWallShelfShapeCommands` (line 178).
- **Inline у `-scene.tsx`:** `enclosed-shelf-scene.tsx:34-123` (BoxGeometry × 4-5 сегментів + InstancedHoles), `perforated-panel-scene.tsx:33-104` (BoxGeometry + ребра + CylinderGeometry corners + InstancedHoles).
- **Причина:** enclosed_shelf і perforated_panel — 2.5D композиції (не свіп-профіль), не мапляться на `ShapeCommand`.
- **Ризик:** refactoring PR на `geometry.ts` пропустить 2 сцени → тихий дрейф.

### F6. `enclosed_shelf` **не експортовано** з `workers/cad/flatcraft_cad/templates/__init__.py`

- **Факт:** `__all__` перелічує 5 з 6 (немає `EnclosedShelfBuildParameters`, `EnclosedShelfTemplate`, `build_enclosed_shelf`).
- **Порятунок:** `unfold.py:26` імпортує напряму (`from flatcraft_cad.templates.enclosed_shelf import ...`).
- **Ризик:** якщо ADR-033 вимагатиме registry-based dispatch, це джерело `AttributeError: enclosed_shelf not in TEMPLATES`.

### F7. `l_bracket` і `enclosed_shelf` — **немає dedicated e2e-spec**

- **Факт:** `apps/web/tests/e2e/` містить `z-bracket.spec.ts`, `corner-angle.spec.ts`, `wall-shelf.spec.ts`, `perforated-panel.spec.ts` — але не `l-bracket.spec.ts` і не `enclosed-shelf.spec.ts`.
- **Порятунок:** `templates.spec.ts` + `template-detail.spec.ts` + `product-closed-shelf-standard.spec.ts` покривають частково.
- **Ризик:** conformance-suite ADR-033 має гарантувати `<slug>.spec.ts` для КОЖНОГО зареєстрованого шаблону (fail-closed).

### F8. `perforated_panel` — SegmentedControl `hole_shape` **над** AutoForm

- **Файл:** `perforated-panel-editor.tsx:84-90`.
- **Причина:** ADR-031 уніфікувала 2 шаблони → `hole_shape: 'circle'|'square'` як параметр; UX вимагає prominent-toggle.
- **Ризик:** якщо `hole_shape` рухнеться в nested object — SegmentedControl мовчки зламається.

---

## 4. Висновки для ADR-033

**Найбільший одиничний copy-paste hotspot:** `field_validator("bend_radius_mm")` у **6 Python-файлах** — константа `ALLOWED_INNER_RADIUS_MM` тільки одна, але сама валідація дуплюється у кожному template'і. Registry-based dispatch дав би `Template.validate_params(params)` як єдиний вхід.

**Найбільший ризик тихого дрейфу:** `bends` контракт (F4) — 3 різні форми (scalar / масив-2 / масив-4 / масив-1-2 / масив-3-4). ADR-033 муситиме зафіксувати `BendsField = scalar | array<BendSpec>` як union у `TemplateDefinition`, або зробити breaking-change.

**Шаблон-виняток:** `enclosed_shelf` вже настільки відхиляється (scene = inline BoxGeometry без `geometry.ts`, немає render-gate, немає e2e-spec, немає у `__all__`), що є кандидат на **окрему registry-гілку** (`ComplexTemplate` extending `TemplateDefinition`) або на **першу міграцію** у Phase 3.5 як «worst case».

**Порядок міграції для Phase 3.5:**

1. `perforated_panel` (найпростіший — grid-based, вже після ADR-031-уніфікації).
2. `corner_angle` (grid-based, дублює l_bracket profile).
3. `l_bracket` (canonical, найбільше знань).
4. `z_bracket` (2 bends, array).
5. `wall_shelf` (F1 — refine у ExportRequest).
6. `enclosed_shelf` (найскладніший — cross-shape, nested opts).

Кожен PR — свій шаблон + `templates/{slug}.spec.ts` (закриває F7) + видалення `<slug>-{editor,viewport,studio}.tsx` + оновлення `TemplateStudioSlug` union (F2).
