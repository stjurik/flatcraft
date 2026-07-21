/**
 * `TEMPLATE_REGISTRY` — єдине джерело істини «які шаблони існують» (ADR-033 §1).
 *
 * ПОКИ ПОРОЖНІЙ (Run 7 Master Registry Track, Етап 1, `docs/promts/master-registry-track.md`):
 * `docs/12_TEMPLATE_CONTRACT.md` §6 фіксує PR 2 (цей пакет) як registry +
 * conformance-suite БЕЗ міграції жодного шаблону — «нуль змін поведінки».
 * Кожен наступний PR Етапу 2 додає РІВНО один slug (порядок — `docs/12` §6:
 * perforated_panel → corner_angle → l_bracket → z_bracket → wall_shelf →
 * enclosed_shelf). Conformance-suite (`test/*.test.ts`) автогенерується з
 * `Object.keys(TEMPLATE_REGISTRY)` — з порожнім реєстром іде 0 ітерацій
 * (зелено, не skip).
 */
import type { TemplateDefinition } from "./definition.js";

export const TEMPLATE_REGISTRY = {} as const satisfies Record<string, TemplateDefinition<unknown>>;

export type TemplateSlug = keyof typeof TEMPLATE_REGISTRY;
