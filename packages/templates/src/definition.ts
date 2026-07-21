/**
 * `TemplateDefinition` — контракт одного зареєстрованого шаблону (ADR-033 §1).
 *
 * `packages/templates` — react-free data-пакет: deps лише `@flatcraft/types` +
 * `@flatcraft/cad-engine` (ADR-033 §1 Рішення 1). `react` — лише type-only
 * імпорт (`ReactNode`) для `kind: 'composed'`/`extraControls` — TS стирає це
 * при компіляції, у runtime-бандл `apps/api` не потрапляє (conformance §3.5
 * перевіряє інваріант автотестом на import-graph).
 */
import type { ProblemError } from "@flatcraft/cad-engine";
import type { ShapeCommand } from "@flatcraft/cad-engine/geometry";
import type { ReactNode } from "react";
import type { z } from "zod";

export type TemplateCapability = "bends" | "profile" | "perforation" | "mount_holes";

/**
 * Generic-viewport будує сцену одним з двох дозволених патернів (ADR-033 §1
 * Рішення 4): `extrude` — 2D `ShapeCommand[]` → `THREE.ExtrudeGeometry`
 * (l_bracket/z_bracket/corner_angle/wall_shelf), `composed` — довільна
 * BoxGeometry-композиція (enclosed_shelf/perforated_panel).
 */
export type SceneBuilderKind<Params> =
  | {
      readonly kind: "extrude";
      readonly build: (params: Params, thicknessMm: number) => ShapeCommand[];
    }
  | {
      readonly kind: "composed";
      readonly render: (params: Params, thicknessMm: number) => ReactNode;
    };

/** Декларативні слоти для editor-UX, які generic AutoForm не покриває сам (ADR-033 §1 Рішення 3). */
export type ExtraControlSpec<Params> =
  | {
      readonly kind: "segmented";
      readonly field: string;
      readonly options: ReadonlyArray<{ readonly value: string; readonly label: string }>;
      readonly label: string;
    }
  | { readonly kind: "summary"; readonly render: (params: Params) => ReactNode }
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
