/**
 * `TemplateDefinition` — контракт одного зареєстрованого шаблону (ADR-033 §1).
 *
 * `packages/templates` — react-free data-пакет: deps лише `@flatcraft/types` +
 * `@flatcraft/cad-engine` (ADR-033 §1 Рішення 1). Жодних `react`-типів (навіть
 * type-only) — виявлено на PR `perforated_panel` (Run 7 Етап 2, docs/12 §1
 * STOP-знахідка 2026-07-21): `render: (...) => ReactNode` семантично повертає
 * JSX, що вимагає `react` як RUNTIME-залежність, не type-only. Тому
 * `SceneBuilderKind.composed` несе лише `{ kind: "composed" }` (реальний
 * компонент — у `@flatcraft/ui/3d-viewport/composed-scenes`, slug-keyed
 * lookup), а `ExtraControlSpec.summary.render` повертає `string`, не
 * `ReactNode`. Conformance §3.5 (`apps/api/src/registry-bundle.test.ts`)
 * перевіряє інваріант автотестом на import-graph.
 */
import type { ProblemError } from "@flatcraft/cad-engine";
import type { ShapeCommand } from "@flatcraft/cad-engine/geometry";
import type { z } from "zod";

export type TemplateCapability = "bends" | "profile" | "perforation" | "mount_holes";

/**
 * Generic-viewport будує сцену одним з двох дозволених патернів (ADR-033 §1
 * Рішення 4): `extrude` — 2D `ShapeCommand[]` → `THREE.ExtrudeGeometry`
 * (l_bracket/z_bracket/corner_angle/wall_shelf), `composed` — довільна
 * BoxGeometry-композиція (enclosed_shelf/perforated_panel), рендерена через
 * `@flatcraft/ui`-side lookup (не тут — react-free, докладніше вище).
 */
export type SceneBuilderKind<Params> =
  | {
      readonly kind: "extrude";
      readonly build: (params: Params, thicknessMm: number) => ShapeCommand[];
    }
  | { readonly kind: "composed" };

/**
 * Декларативні слоти для editor-UX, які generic AutoForm не покриває сам
 * (ADR-033 §1 Рішення 3). `testId` — обов'язковий (не вгадується з `field`/
 * `slug`, щоб не ламати наявні e2e-testid при міграції — напр. перфо-панелі
 * grid-summary testid `grid-summary`, не `perforated-panel-summary`).
 */
export type ExtraControlSpec<Params> =
  | {
      readonly kind: "segmented";
      readonly field: string;
      readonly options: ReadonlyArray<{ readonly value: string; readonly label: string }>;
      readonly label: string;
      readonly testId: string;
    }
  | {
      readonly kind: "summary";
      readonly render: (params: Params) => string;
      readonly testId: string;
    }
  | { readonly kind: "hint"; readonly field: string; readonly text: string };

/**
 * Server-side-паритетний валідатор (ADR-019 + ADR-026 render-gate) — повертає
 * RFC 9457 `ProblemError[]` (той самий формат, що вже дає `validateExportProfile`/
 * `validateExportPerforation`/`validateExportBends` у Fastify-gate). Порожній
 * масив = валідно. Generic-viewport НЕ рендерить `<Canvas>` при непорожньому
 * результаті (render-gate ADR-026); generic-editor блокує export-кнопку.
 */
export type ProfileValidator<Params> = (
  params: Params,
  thicknessMm: number,
) => readonly ProblemError[];

/** Продукт (preset) поверх шаблону — ADR-027: фіксовані параметри + підмножина, яку редагує користувач. */
export interface ProductDefinition<Params> {
  readonly slug: string;
  readonly name: string;
  readonly description: string | null;
  readonly fixed: Partial<Params>;
  readonly userEditableFields: ReadonlyArray<keyof Params & string>;
}

export interface TemplateDefinition<Params> {
  /** Унікальний, kebab_case (існуючі шаблони — snake_case slug, напр. `l_bracket`). */
  readonly slug: string;
  /** Константа поки — ADR-034 (Process layer) зробить це union'ом. */
  readonly process: "sheet_metal";
  /**
   * Локалізовані лейбли назви шаблону (ADR-037 §5 Consequence, Run 7 Етап 1):
   * Etap B (i18n студій) споживає це напряму — заповнюється ОБОВ'ЯЗКОВО для
   * кожного шаблону, що мігрує на реєстр (Etap 2), щоб студії не лишились
   * частково-локалізованими після Registry.
   */
  readonly labels: { readonly uk: string; readonly en: string };
  /** Повна refined-Zod (без Base-варіанту, ADR-033 §2 ALT-C). */
  readonly schema: z.ZodType<Params>;
  readonly defaults: Params;
  readonly ui: {
    readonly scene: SceneBuilderKind<Params>;
    readonly extraControls?: ReadonlyArray<ExtraControlSpec<Params>>;
    /** Для product-mode (ADR-027 Рішення 4). */
    readonly visibleFields?: readonly string[];
    /** `/public/thumbs/{thumbSlug ?? slug}.png`. */
    readonly thumbSlug?: string;
  };
  readonly validators: ReadonlyArray<ProfileValidator<Params>>;
  readonly products?: ReadonlyArray<ProductDefinition<Params>>;
  readonly capabilities: readonly TemplateCapability[];
}
