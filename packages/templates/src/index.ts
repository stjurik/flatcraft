/**
 * @flatcraft/templates — Template Registry (ADR-033).
 *
 * React-free data-пакет: `TemplateDefinition` + `TEMPLATE_REGISTRY`. Один
 * зареєстрований шаблон = 1 TS-модуль (тут) + 1 Python-модуль (`workers/cad`)
 * + снапшоти + автогенерований conformance-suite (`docs/12_TEMPLATE_CONTRACT.md`).
 */
export {
  type ExtraControlSpec,
  type ProductDefinition,
  type ProfileValidator,
  type SceneBuilderKind,
  type TemplateCapability,
  type TemplateDefinition,
} from "./definition.js";

export { TEMPLATE_REGISTRY, type TemplateSlug } from "./registry.js";
