/**
 * `TEMPLATE_REGISTRY` — єдине джерело істини «які шаблони існують» (ADR-033 §1).
 *
 * Run 7 Master Registry Track, Етап 2 (docs/promts/master-registry-track.md):
 * кожен PR додає РІВНО один slug (порядок — `docs/12_TEMPLATE_CONTRACT.md` §6:
 * perforated_panel → corner_angle → l_bracket → z_bracket → wall_shelf →
 * enclosed_shelf). Після кожного додавання: `pnpm --filter @flatcraft/templates
 * run export-registry` (регенерує `workers/cad/tests/fixtures/ts_registry_slugs.json`
 * для slug-паритету TS↔Python).
 */
import { cornerAngleDefinition } from "./corner-angle/index.js";
import { perforatedPanelDefinition } from "./perforated-panel/index.js";

// Без `satisfies Record<string, TemplateDefinition<X>>` (Етап 1 мало це для
// порожнього `{}`): `Params` у TemplateDefinition з'являється і коваріантно
// (`defaults`, `schema`-output), і контраваріантно (`validators`/`build`
// параметри) — жоден єдиний X не задовольнить обидві позиції одночасно для
// різнотипних записів (`unknown` ламає контраваріантні, `never` — коваріантні).
// Типобезпека — на рівні кожного окремого визначення (`perforatedPanelDefinition:
// TemplateDefinition<PerforatedPanelParameters>`, перевірено у своєму файлі).
export const TEMPLATE_REGISTRY = {
  perforated_panel: perforatedPanelDefinition,
  corner_angle: cornerAngleDefinition,
} as const;

export type TemplateSlug = keyof typeof TEMPLATE_REGISTRY;
