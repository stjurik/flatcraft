"use client";

import { validateProfile, type ProblemError, type ProfileIssue } from "@flatcraft/cad-engine";
import type { MaterialChoice } from "@flatcraft/types";
import {
  MaterialSection,
  useDebouncedValue,
  useIsMobile,
  useReducedMotion,
  viewportQuality,
  type MaterialSelection,
} from "@flatcraft/ui";
import { useMemo, useState, type ReactNode } from "react";
import type { z } from "zod";

import { bendMatrixIssues } from "../lib/bend-matrix";

import { ExportButton } from "./export-button";
import { StudioPreviewAnchor } from "./studio-preview-anchor";

/** Slug'и, проти яких ми ведемо validateProfile / bendMatrixIssues. */
export type TemplateStudioSlug =
  | "l_bracket"
  | "z_bracket"
  | "corner_angle"
  | "wall_shelf"
  | "perforated_panel";

export interface EditorRenderProps<T> {
  readonly value: T;
  readonly onChange: (next: T) => void;
  readonly materialCode: string;
  readonly thicknessMm: number;
  /** Phase 3.0 PR 4: filter полів для product-mode (ADR-027 Рішення 4). */
  readonly visibleFields?: readonly string[];
}

export interface ViewportRenderProps<T> {
  readonly parameters: T;
  readonly thicknessMm: number;
}

export interface TemplateStudioProductMeta {
  /** Name виробу для header (наприклад, «Декоративна перфо-панель»). */
  readonly name: string;
  /** Markdown-опис продукту (для header'а). */
  readonly description: string | null;
  /** Параметри, які виробник фіксує — мерджаться поверх userInput у setParameters. */
  readonly fixedParameters: Record<string, unknown>;
  /** Поля, які користувач редагує — AutoForm рендерить тільки їх. */
  readonly userEditableFields: readonly string[];
}

export interface TemplateStudioProps<T extends Record<string, unknown>> {
  readonly mode: "part" | "product";
  readonly templateSlug: TemplateStudioSlug;
  readonly initialParameters: T;
  readonly materials: ReadonlyArray<MaterialChoice>;
  /**
   * Schema базового шаблону для перевірки isValid (safeParse). Тип навмисно
   * широкий (z.ZodTypeAny): ZodObject з .default()/.refine() — це різні Zod
   * типи з incompatible Input/Output, але для safeParse'у достатньо щоб метод
   * існував. Caller ↔ T consistency гарантована на site of каструвальника.
   */
  readonly schema: z.ZodTypeAny;
  /** testId на root container — `${slug}-studio` за конвенцією. */
  readonly testId: string;
  /** Editor — рендериться у лівій колонці; знає, як побудувати поля для T. */
  readonly renderEditor: (props: EditorRenderProps<T>) => ReactNode;
  /** Viewport — рендериться у правій колонці. */
  readonly renderViewport: (props: ViewportRenderProps<T>) => ReactNode;
  /**
   * Phase 3.0 PR 4: product-mode meta. Обов'язкове коли mode='product'.
   * НЕ використовується у part-mode (ігнорується).
   */
  readonly product?: TemplateStudioProductMeta;
}

const DEFAULT_MATERIAL_CODE = "cold_rolled_steel";
const DEFAULT_THICKNESS_MM = 2.0;

const SLUGS_WITH_BENDS: ReadonlySet<TemplateStudioSlug> = new Set([
  "l_bracket",
  "z_bracket",
  "corner_angle",
  "wall_shelf",
]);

const SLUGS_WITH_PROFILE: ReadonlySet<TemplateStudioSlug> = new Set([
  "l_bracket",
  "z_bracket",
  "corner_angle",
  "wall_shelf",
]);

/**
 * Shared studio контейнер для всіх 5 шаблонів — Phase 3.0 PR 4 (ADR-027 Рішення 3).
 *
 * mode='part' (default flow): рендериться повна форма; user стартує з
 * initialParameters і змінює всі поля. Збереження поведінки Phase 2.10.
 *
 * mode='product' (PR 6+): рендериться header з product.name + AutoForm з
 * `visibleFields={product.userEditableFields}`. User'ський вхід мерджиться
 * з product.fixedParameters перед передачею у viewport/export. (Тут не
 * викликаємо `resolveProductParams` явно — merge відбувається при setParameters,
 * щоб state завжди містив повні params; защита від обходу — на сервері.)
 *
 * Валідація:
 *   - schema.safeParse: завжди (UX-gate проти Zod-помилок).
 *   - bendMatrixIssues: лише для шаблонів з гибами (perforated_panel пропускає).
 *   - validateProfile: лише для шаблонів з геометричними assertion'ами
 *     (perforated_panel — плоский, без profile-gate).
 */
export function TemplateStudio<T extends Record<string, unknown>>({
  mode,
  templateSlug,
  initialParameters,
  materials,
  schema,
  testId,
  renderEditor,
  renderViewport,
  product,
}: TemplateStudioProps<T>) {
  // Phase 3.0 PR 4: у product-mode initialParameters — це resolved start
  // (fixed + defaults). Setter merge'ить з fixed щоразу, щоб user не міг
  // обійти fixed через React DevTools.
  const initialResolved = useMemo<T>(() => {
    if (mode === "product" && product) {
      return { ...initialParameters, ...product.fixedParameters } as T;
    }
    return initialParameters;
  }, [mode, product, initialParameters]);

  const [parameters, setParametersState] = useState<T>(initialResolved);

  const setParameters = (next: T) => {
    // product-mode: завжди мерджимо поверх fixed (захист від випадкового
    // override через AutoForm).
    if (mode === "product" && product) {
      setParametersState({ ...next, ...product.fixedParameters } as T);
    } else {
      setParametersState(next);
    }
  };

  const [material, setMaterial] = useState<MaterialSelection>({
    materialCode: DEFAULT_MATERIAL_CODE,
    thicknessMm: DEFAULT_THICKNESS_MM,
  });
  const isMobile = useIsMobile();
  const reduced = useReducedMotion();
  const quality = useMemo(() => viewportQuality({ isMobile, reduced }), [isMobile, reduced]);
  const debouncedParameters = useDebouncedValue(parameters, quality.debounceMs);

  const isValid = useMemo(() => schema.safeParse(parameters).success, [schema, parameters]);

  const matrixIssues = useMemo<readonly ProblemError[]>(() => {
    if (!SLUGS_WITH_BENDS.has(templateSlug)) return [];
    return bendMatrixIssues({
      template_slug: templateSlug,
      parameters,
      material_code: material.materialCode,
      thickness_mm: material.thicknessMm,
      // T — generic Record<string, unknown>; ExportRequest очікує union типів
      // конкретних шаблонів. Caller гарантує консистентність slug↔T.
    } as unknown as Parameters<typeof bendMatrixIssues>[0]);
  }, [templateSlug, parameters, material.materialCode, material.thicknessMm]);

  const profileIssues = useMemo<readonly ProfileIssue[]>(() => {
    if (!SLUGS_WITH_PROFILE.has(templateSlug)) return [];
    return validateProfile({
      templateSlug,
      parameters,
      thicknessMm: material.thicknessMm,
    } as unknown as Parameters<typeof validateProfile>[0]);
  }, [templateSlug, parameters, material.thicknessMm]);

  const exportDisabled = !isValid || matrixIssues.length > 0 || profileIssues.length > 0;

  return (
    <div data-testid={testId} className="flex flex-col gap-4">
      {mode === "product" && product ? (
        <header data-testid="product-studio-header" className="border-border border-b pb-3">
          <h2 className="font-display text-fg text-2xl font-semibold">{product.name}</h2>
          {product.description ? (
            <p className="text-fg-muted mt-1 text-sm">{product.description}</p>
          ) : null}
        </header>
      ) : null}

      <div className="grid gap-6 lg:grid-cols-[1fr_2fr]">
        <div className="flex flex-col gap-4">
          <MaterialSection materials={materials} value={material} onChange={setMaterial} />
          <StudioPreviewAnchor />
          {renderEditor({
            value: parameters,
            onChange: setParameters,
            materialCode: material.materialCode,
            thicknessMm: material.thicknessMm,
            ...(mode === "product" && product ? { visibleFields: product.userEditableFields } : {}),
          })}
          <ExportButton
            request={
              // ExportRequest — z.discriminatedUnion: parameters має точний тип
              // per template_slug. Generic T тут не вписується у union — каст
              // безпечний, бо template_slug і parameters йдуть з одного контексту
              // консумера (l-bracket-studio передає LBracketParameters з l_bracket
              // slug'ом тощо).
              {
                template_slug: templateSlug,
                parameters,
                material_code: material.materialCode,
                thickness_mm: material.thicknessMm,
              } as unknown as Parameters<typeof ExportButton>[0]["request"]
            }
            disabled={exportDisabled}
          />
        </div>

        {renderViewport({ parameters: debouncedParameters, thicknessMm: material.thicknessMm })}
      </div>
    </div>
  );
}
