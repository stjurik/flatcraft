/**
 * Хелпери для клієнтського перемикача форми отвору перфо-панелі
 * (круг ↔ квадрат) — Варіант B: над двома шаблонами без змін backend.
 *
 * Два шаблони лишаються окремими (`perforated_panel` = круглі/`hole_diameter_mm`,
 * `perforated_panel_square` = квадратні/`hole_size_mm`). Студія тримає ОБИДВА
 * ключі розміру синхронно, тож перемикання форми (slug+schema+viewport)
 * не втрачає значень. Активна Zod-схема читає свій ключ; зайвий відкидається
 * при `safeParse` (UX) і при парсингу `ExportRequestSchema` на API.
 */
import {
  PERFORATED_PANEL_DEFAULT_PARAMETERS,
  PERFORATED_PANEL_SQUARE_DEFAULT_PARAMETERS,
  PerforatedPanelParametersSchema,
  PerforatedPanelSquareParametersSchema,
  type PerforatedPanelParameters,
  type PerforatedPanelSquareParameters,
} from "@flatcraft/types";
import type { z } from "zod";

export type HoleShape = "circle" | "square";

export type PerforationSlug = "perforated_panel" | "perforated_panel_square";

/**
 * Спільний param-стан студії: обидва ключі розміру отвору присутні й рівні.
 * Перетин типів двох шаблонів = усі поля (length/width/pitch_x/pitch_y/margin
 * + hole_diameter_mm + hole_size_mm).
 */
export type PerforationParameters = PerforatedPanelParameters & PerforatedPanelSquareParameters;

export function slugForHoleShape(shape: HoleShape): PerforationSlug {
  return shape === "square" ? "perforated_panel_square" : "perforated_panel";
}

export function holeShapeFromSlug(slug: string): HoleShape {
  return slug === "perforated_panel_square" ? "square" : "circle";
}

export function schemaForHoleShape(shape: HoleShape): z.ZodObject<z.ZodRawShape> {
  return shape === "square"
    ? PerforatedPanelSquareParametersSchema
    : PerforatedPanelParametersSchema;
}

/** Назва поля розміру отвору для активної форми (для visibleFields/лейблів). */
export function holeSizeFieldFor(shape: HoleShape): "hole_diameter_mm" | "hole_size_mm" {
  return shape === "square" ? "hole_size_mm" : "hole_diameter_mm";
}

/**
 * Дзеркалить значення розміру отвору в ОБИДВА ключі. `activeShape` — форма,
 * яку щойно редагували (її ключ — джерело істини).
 */
export function syncHoleKeys(
  params: PerforationParameters,
  activeShape: HoleShape,
): PerforationParameters {
  const value =
    activeShape === "square"
      ? (params.hole_size_mm ?? params.hole_diameter_mm)
      : (params.hole_diameter_mm ?? params.hole_size_mm);
  return { ...params, hole_diameter_mm: value, hole_size_mm: value };
}

/**
 * Стартові params з обома ключами розміру. `base` — defaults з роута/продукту
 * (round- або square-форми); відсутні поля доповнюються дефолтами обох шаблонів.
 */
export function initialPerforationParams(
  shape: HoleShape,
  base: Partial<PerforationParameters>,
): PerforationParameters {
  const merged = {
    ...PERFORATED_PANEL_DEFAULT_PARAMETERS,
    ...PERFORATED_PANEL_SQUARE_DEFAULT_PARAMETERS,
    ...base,
  } as PerforationParameters;
  return syncHoleKeys(merged, shape);
}

/**
 * Нормалізує product `visibleFields`: замінює будь-який ключ розміру отвору на
 * активний (щоб список, заданий для квадратної форми, працював і для круглої).
 */
export function normalizeVisibleFields(
  visibleFields: readonly string[] | undefined,
  shape: HoleShape,
): readonly string[] | undefined {
  if (!visibleFields) return visibleFields;
  const active = holeSizeFieldFor(shape);
  const replaced = visibleFields.map((f) =>
    f === "hole_diameter_mm" || f === "hole_size_mm" ? active : f,
  );
  return Array.from(new Set(replaced));
}
