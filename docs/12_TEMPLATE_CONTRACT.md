# 12. Template Contract — специфікація Template Registry (ADR-033)

> **Статус:** Proposed (2026-07-13, разом з ADR-033). До прийняття ADR-033 — референс, не інваріант.
>
> Мета: **новий шаблон = 1 TS-модуль + 1 Python-модуль + снапшоти + автогенерований spec**. Нуль правок у `apps/web`, `apps/api`. Це специфікація контракту (Що і Як), а не implementation-план (він у Roadmap Phase 3.5).

## 1. `TemplateDefinition` (TypeScript-контракт)

> **Реалізовано (Run 7 Master Registry Track, Етап 1, `feat/registry-core`):** блок нижче
> оновлено з реального коду `packages/templates/src/definition.ts` (був аспіраційним
> псевдокодом до цього PR). Два усвідомлені відхилення від початкового ескізу —
> занесені в «Опитування» PR, не STOP-тригер (семантика контракту не змінилась):
>
> - `ProfileValidator<Params>` живе у `packages/templates` (не в `@flatcraft/cad-engine/validators`,
>   як у первісному ескізі) — тип generic над `Params`, який `cad-engine` не знає;
>   повертає вже наявний `ProblemError` з `@flatcraft/cad-engine` (той самий RFC 9457
>   формат, що й `validateExportProfile`/`validateExportPerforation`/`validateExportBends`),
>   замість введення нового issue-типу.
> - `ProductDefinition.fixed` (не `fixedParameters`, як у `TemplateStudioProductMeta`
>   в `apps/web`) — назва поля дослівно з ADR-033 §5 CONSEQUENCES («fixed,
>   userEditableFields»).

```ts
// packages/templates/src/definition.ts (новий пакет, ADR-033 §1)
import type { ProblemError } from "@flatcraft/cad-engine";
import type { ShapeCommand } from "@flatcraft/cad-engine/geometry"; // ПЕРЕЇХАВ з @flatcraft/ui у PR 2 (ADR-033 §1: react-free реєстр)
import type { ReactNode } from "react";
import type { z } from "zod";

export type TemplateCapability = "bends" | "profile" | "perforation" | "mount_holes";

export type SceneBuilderKind<Params> =
  | { kind: "extrude"; build: (params: Params, thicknessMm: number) => ShapeCommand[] }
  | { kind: "composed"; render: (params: Params, thicknessMm: number) => ReactNode };

export type ExtraControlSpec<Params> =
  | { kind: "segmented"; field: string; options: { value: string; label: string }[]; label: string }
  | { kind: "summary"; render: (params: Params) => ReactNode }
  | { kind: "hint"; field: string; text: string };

// ADR-019 + ADR-026 render-gate: RFC 9457 ProblemError[] — той самий формат,
// що вже дає validateExportProfile/validateExportPerforation/validateExportBends.
export type ProfileValidator<Params> = (
  params: Params,
  thicknessMm: number,
) => readonly ProblemError[];

export interface ProductDefinition<Params> {
  // ADR-027: fixed + userEditableFields.
  slug: string;
  name: string;
  description: string | null;
  fixed: Partial<Params>;
  userEditableFields: ReadonlyArray<keyof Params & string>;
}

export interface TemplateDefinition<Params> {
  slug: string; // унікальний, kebab-case (наявні шаблони — snake_case, напр. l_bracket)
  process: "sheet_metal"; // constant поки — ADR-034 зробить це union'ом
  schema: z.ZodType<Params>; // повна refined-Zod (без Base-варіанту)
  defaults: Params;
  ui: {
    scene: SceneBuilderKind<Params>;
    extraControls?: ExtraControlSpec<Params>[]; // F8 SegmentedControl, wall-shelf summary
    visibleFields?: string[]; // для product-mode (ADR-027)
    thumbSlug?: string; // /public/thumbs/{slug}.png (default = slug)
  };
  validators: ProfileValidator<Params>[]; // ADR-019 + ADR-026 render-gate
  products?: ProductDefinition<Params>[]; // ADR-027 (fixed + userEditableFields)
  capabilities: TemplateCapability[]; // 'bends' | 'profile' | 'perforation' | ...
}
```

### Deps `packages/templates` (ADR-033 §1)

- **Runtime deps:** `@flatcraft/types` + `@flatcraft/cad-engine`. **НЕ** `@flatcraft/ui`.
- **Type-only deps:** `zod`, `react` (лише `type { ReactNode }` для `kind: 'composed'` — TS-strip'ає при компіляції, у runtime-bundle `apps/api` не потрапляє).
- **Наслідок для міграції:** тип `ShapeCommand` у PR 2 переїжджає з `packages/ui/src/3d-viewport/geometry.ts` у `packages/cad-engine/src/geometry/*` (це data-контракт для sceneBuilder-ів, не UI-код). `packages/ui` стає споживачем реєстру (generic-viewport), а не залежністю.
- **Обов'язковий інваріант (§5):** import реєстру у `apps/api` НЕ тягне `react`/`react-dom`. Захищено §3.5.

### Registry (compile-time typed)

```ts
// packages/templates/src/registry.ts
export const TEMPLATE_REGISTRY = {
  l_bracket: lBracketDefinition,
  z_bracket: zBracketDefinition,
  corner_angle: cornerAngleDefinition,
  wall_shelf: wallShelfDefinition,
  enclosed_shelf: enclosedShelfDefinition,
  perforated_panel: perforatedPanelDefinition,
} as const satisfies Record<string, TemplateDefinition<unknown>>;

export type TemplateSlug = keyof typeof TEMPLATE_REGISTRY;
```

`TemplateSlug` типізовано з ключів реєстру — hardcoded union у `template-studio.tsx:29-35` (C1 F2 hotspot #2) видаляється.

### ExportRequest (ADR-033 §2, ALT-C)

```ts
export const ExportRequestSchema = z
  .object({
    slug: z.enum(Object.keys(TEMPLATE_REGISTRY) as [string, ...string[]]),
    params: z.unknown(),
  })
  .superRefine((v, ctx) => {
    const def = TEMPLATE_REGISTRY[v.slug as TemplateSlug];
    const parsed = def.schema.safeParse(v.params);
    if (!parsed.success)
      parsed.error.issues.forEach((i) => ctx.addIssue({ ...i, path: ["params", ...i.path] }));
  });
```

Це замінює `discriminatedUnion` у `packages/types/src/domain/export.ts` — F1 (WallShelfBaseSchema) закривається.

## 2. Python-контракт (paritet)

```python
# workers/cad/flatcraft_cad/templates/registry.py (новий модуль, ADR-033 §5)
from flatcraft_cad.templates.base import Template
from flatcraft_cad.templates.l_bracket import LBracketTemplate
from flatcraft_cad.templates.z_bracket import ZBracketTemplate
from flatcraft_cad.templates.corner_angle import CornerAngleTemplate
from flatcraft_cad.templates.wall_shelf import WallShelfTemplate
from flatcraft_cad.templates.enclosed_shelf import EnclosedShelfTemplate
from flatcraft_cad.templates.perforated_panel import PerforatedPanelTemplate

TEMPLATES: dict[str, type[Template]] = {
    "l_bracket":        LBracketTemplate,
    "z_bracket":        ZBracketTemplate,
    "corner_angle":     CornerAngleTemplate,
    "wall_shelf":       WallShelfTemplate,
    "enclosed_shelf":   EnclosedShelfTemplate,
    "perforated_panel": PerforatedPanelTemplate,
}
```

`enclosed_shelf` тепер обов'язково у dict — F6 закривається.

### `Template` base (розширення `base.py`)

```python
class Template[ParamsT: BaseModel](ABC):
    name: str
    params_model: type[ParamsT]

    @abstractmethod
    def build(self, params: ParamsT) -> cq.Workplane: ...

    @abstractmethod
    def unfold(self, params: ParamsT) -> "Unfolded": ...      # Union[UnfoldedProfile, UnfoldedCross]

    @abstractmethod
    def to_dxf(self, unfolded, params: ParamsT) -> bytes: ... # генерик через unfold-type

    @abstractmethod
    def to_pdf(self, unfolded, params: ParamsT) -> bytes: ...

    def validate_params(self, params: ParamsT) -> list[ProfileIssue]:
        """Server-side validator (parity з TS `def.validators`)."""
        return []
```

Функції `build_*`, `unfold_*`, `to_dxf_*` з поточних `templates/*.py` мігрують у методи класу. `export/{dxf,pdf}.py` дискримінує через `TEMPLATES[slug].to_dxf(...)`, а не через `if template_slug == '...'`.

## 3. Conformance-suite (ADR-033 §6, автогенерована з реєстру)

Кожен зареєстрований шаблон **автоматично** отримує 4 перевірки:

### 3.1. Schema parity TS ↔ Python (property-based)

- **TS-side (`packages/templates/test/parity.test.ts`):** для кожного slug згенерувати 100 випадкових об'єктів через `fast-check`, серіалізувати у JSON, дати worker'у → `Pydantic.model_validate_json` = OK.
- **Python-side (`workers/cad/tests/test_registry_parity.py`):** через `hypothesis` згенерувати Pydantic-моделі, серіалізувати → TS-schema safeParse = OK (через RPC-тестфікстуру).
- **Slug parity:** `set(TS_REGISTRY.keys()) == set(PY_REGISTRY.keys())` — падає, якщо один додано, інший ні.

### 3.2. DXF/PDF детермінізм

Патерн існуючих pytest-снапшотів у `workers/cad/tests/`:

```python
@pytest.mark.parametrize("slug", TEMPLATES.keys())
def test_dxf_deterministic(slug, snapshot):
    tpl = TEMPLATES[slug]()
    params = tpl.params_model(**FIXTURE_DEFAULTS[slug])
    unfolded = tpl.unfold(params)
    dxf_bytes = tpl.to_dxf(unfolded, params)
    assert dxf_bytes == snapshot(name=f"{slug}.dxf")  # bytes literal
```

Той самий фіксований seed → той самий байт-у-байт вихід. Інваріант CLAUDE.md §2.4.

### 3.3. Render-gate (клієнт)

```ts
// packages/templates/test/render-gate.test.ts
test.each(Object.keys(TEMPLATE_REGISTRY))("render-gate rejects invalid %s", (slug) => {
  const def = TEMPLATE_REGISTRY[slug as TemplateSlug];
  const INVALID = { ...def.defaults, thickness_mm: 999 }; // явно поза матрицею
  const issues = def.validators.flatMap((v) => v(INVALID));
  expect(issues.length).toBeGreaterThan(0); // render-gate стрельне
});
```

- `R3FErrorBoundary` як backstop у generic-viewport (ADR-026).

### 3.4. e2e smoke (Playwright)

```ts
// apps/web/tests/e2e/registry.spec.ts (автогенерований)
for (const slug of Object.keys(TEMPLATE_REGISTRY)) {
  test(`studio smoke — ${slug}`, async ({ page }) => {
    await page.goto(`/templates/${slug}`);
    await expect(page.getByRole("heading")).toBeVisible();
    // Змінити перший number-input, перевірити що ExportButton не disabled
    await page.locator('input[type="number"]').first().fill("50");
    await expect(page.getByRole("button", { name: /експорт|export/i })).not.toBeDisabled();
  });
}
```

Закриває F7 (`l_bracket`, `enclosed_shelf` тепер мають coverage).

### 3.5. React-free import у `apps/api` (bundle inclusion)

`packages/templates` — data-пакет. Реєстр повинен вантажитись у `apps/api` (Node.js, Fastify) БЕЗ React у бандлі. Порушення інваріанта = React у request-path сервера (bundle-size, startup, стороння runtime-залежність).

```ts
// apps/api/tests/registry-bundle.test.ts (додається у PR 2 разом з реєстром)
import { parseImportGraph } from "./helpers/import-graph"; // esbuild-metafile або madge

test("registry import у apps/api НЕ тягне react/react-dom", async () => {
  const graph = await parseImportGraph("apps/api/src/routes/exports.ts");
  expect(graph.modules).not.toEqual(expect.arrayContaining(["react", "react-dom"]));
});
```

Реалізація: bundle `apps/api` через esbuild з `--metafile`, парсити метафайл, перевіряти відсутність `react*` у списку модулів. Альтернативно — `madge --json`. Fail-closed CI.

## 4. Definition of Done нового шаблону

**Чекліст для промпту «Додай шаблон `<slug>`»:**

- [ ] **1. TS-definition:** `packages/templates/src/<slug>/index.ts` — експортує `<slug>Definition: TemplateDefinition<Params>` з усіма полями (schema, defaults, ui, validators, capabilities). НЕ додавати файлів у `apps/web/src/components/*-{studio,editor,viewport}.tsx`.
- [ ] **2. Registry entry (TS):** додати slug у `TEMPLATE_REGISTRY` (`packages/templates/src/registry.ts`).
- [ ] **3. Python module:** `workers/cad/flatcraft_cad/templates/<slug>.py` — `<Slug>Template(Template[<Slug>BuildParameters])` з методами `build`, `unfold`, `to_dxf`, `to_pdf`, `validate_params`.
- [ ] **4. Registry entry (Python):** додати slug у `TEMPLATES` dict (`workers/cad/flatcraft_cad/templates/registry.py`).
- [ ] **5. Снапшоти DXF/PDF:** `workers/cad/tests/snapshots/<slug>.dxf.snap`, `<slug>.pdf.snap` — згенеровано з `FIXTURE_DEFAULTS[slug]`.
- [ ] **6. Продукт-варіанти (опційно):** якщо шаблон має preset'и (ADR-027) — `def.products = [...]`.
- [ ] **7. Seed:** `packages/db/src/seed.ts` — додати запис у `templates` таблицю.
- [ ] **8. Conformance suite:** усі 4 перевірки з §3 зелені **автоматично** (нічого не писати вручну — реєстр + фікстури).
- [ ] **9. Thumb:** `apps/web/public/thumbs/<slug>.png` (опційно; default — placeholder).
- [ ] **10. Docs:** нема окремого docs-файлу — definition містить `.describe()` як єдине джерело.

**НЕ треба:**

- ~~`<slug>-studio.tsx`~~, ~~`<slug>-editor.tsx`~~, ~~`<slug>-viewport.tsx`~~
- ~~`<slug>-scene.tsx`~~ (для kind:'extrude' — використовує generic; для kind:'composed' — inline у definition.ui.scene.render)
- ~~Гілки у `if template_slug == '<slug>'` у `unfold.py` / `dxf.py` / `pdf.py`~~ (all dispatch through registry)
- ~~Оновлення `TemplateStudioSlug` union~~ (auto-generated)
- ~~Оновлення `SLUGS_WITH_BENDS` / `SLUGS_WITH_PERFORATION` set-ів~~ (замінено на `def.capabilities`)

**Definition of Done PR = усі 10 чекбоксів + green CI + conformance-suite green.**

## 5. Інваріанти, які контракт НЕ сміє ламати

| Інваріант                                | Джерело        | Як контракт зберігає                                                                                     |
| ---------------------------------------- | -------------- | -------------------------------------------------------------------------------------------------------- |
| Байт-у-байт DXF/PDF                      | CLAUDE.md §2.4 | conformance §3.2 — снапшот-тести; жодних правок у `to_dxf`/`to_pdf` при міграції шаблону                 |
| Render-gate ADR-026                      | ADR-026        | generic-viewport ЗАВЖДИ виклик `validateProfile()` через `def.validators`; `R3FErrorBoundary` — backstop |
| Products ADR-027                         | ADR-027        | `def.products?: ProductDefinition[]` — те саме shape'ом (`fixed`, `userEditableFields`)                  |
| Browser-safe entry `packages/cad-engine` | CLAUDE.md §13  | `packages/templates` НЕ імпортує `node:*`; `fs`-loader — тільки через subpath `/node`                    |
| Server-side validation ADR-019           | ADR-019        | Fastify-gate викликає `def.validators` через registry ДО постановки job'а в BullMQ                       |
| React-free реєстр                        | ADR-033 §1     | conformance §3.5 — import-graph `apps/api/src/routes/exports.ts` не містить `react`/`react-dom`          |

Порушення будь-якого — конформанс-суита червона у CI.

## 6. Міграційний план (реалізаційна частина — Roadmap Phase 3.5)

Порядок PR-ів (обгрунтовано у C1 §4 і ADR-033 §CONSEQUENCES):

| PR  | Зміст                                                                                                                                                                                                                                                                            |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | ADR-033 + `docs/12_TEMPLATE_CONTRACT.md` + Roadmap 3.5 checklist (**цей PR**, docs-only)                                                                                                                                                                                         |
| 2   | `packages/templates` — новий пакет: `TemplateDefinition`, `TEMPLATE_REGISTRY` (порожній), conformance-suite (у т.ч. §3.5 react-free); **перенесення `ShapeCommand` з `packages/ui/src/3d-viewport/geometry.ts` у `packages/cad-engine`** (споживачі-import'и `apps/web` оновити) |
| 3   | Мігрувати `perforated_panel` (найпростіший, вже після ADR-031-уніфікації)                                                                                                                                                                                                        |
| 4   | Мігрувати `corner_angle` (grid-based, дублює `l_bracket` profile)                                                                                                                                                                                                                |
| 5   | Мігрувати `l_bracket` (canonical); ExportRequest переходить на superRefine (F1 закривається)                                                                                                                                                                                     |
| 6   | Мігрувати `z_bracket` (2 bends, array)                                                                                                                                                                                                                                           |
| 7   | Мігрувати `wall_shelf` (переніс refine `front_lip_mm` у definition; F1 остаточно закрито)                                                                                                                                                                                        |
| 8   | Мігрувати `enclosed_shelf` (найскладніший — cross-shape + nested opts; F2 закрито render-gate'ом)                                                                                                                                                                                |
| 9   | Cleanup: видалити `apps/web/src/components/*-{studio,editor,viewport}.tsx` × 18 файлів, `SLUGS_WITH_*` set-и                                                                                                                                                                     |

**Правило кожного PR №3-8:** conformance-suite для ЦЬОГО шаблону зелена; існуючі шаблони — все ще працюють через `if slug in TEMPLATE_REGISTRY: registry-path else: legacy-path` (dual-run під час міграції). E2e для всіх шаблонів зелений після КОЖНОГО PR.
