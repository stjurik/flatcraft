/**
 * Реекспорт Template Registry для `apps/api` (ADR-033 §1, §3.5).
 *
 * Це точка входу, яку `registry-bundle.test.ts` бандлить через esbuild, щоб
 * гарантувати інваріант: `@flatcraft/templates` (react-free data-пакет)
 * НЕ тягне `react`/`react-dom` у серверний Node.js-бандл. Фактичне
 * використання реєстру у бізнес-логіці `routes/exports.ts` (заміна
 * `discriminatedUnion` на `superRefine`, ADR-033 §2) підключається поступово
 * під час міграції шаблонів (Run 7 Етап 2, docs/12_TEMPLATE_CONTRACT.md §6,
 * PR l_bracket) — до того цей файл лишається тонким реекспортом.
 */
export { TEMPLATE_REGISTRY, type TemplateSlug } from "@flatcraft/templates";
