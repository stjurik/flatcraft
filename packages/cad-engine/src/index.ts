/**
 * @flatcraft/cad-engine — валідатори листового металу, K-фактор, завантажувач
 * bend-machine spec, утиліти геометрії.
 *
 * Реальний код по фазам:
 *   - Phase 1.2 (поточна): spec.ts — завантажувач + Zod-схема.
 *   - Phase 1.3: validators/ — validateBend, validateSheet, validateHoles.
 *   - Phase 1.4: k-factor.ts — обчислення K за матеріалом + R/S.
 *   - Phase 2.6: opencascade-bridge.ts.
 * Дані обладнання — у data/bend-machine-esi.yaml.
 */

// Головний entry — browser-safe. Файловий loader (`loadSpecFromFile`) живе у
// subpath `@flatcraft/cad-engine/node` (node:fs). Браузер бере `bakedSpec`.
export { BendMachineSpecSchema, loadSpec, type BendMachineSpec } from "./spec.js";
export { bakedSpec } from "./generated/baked-spec.js";

export {
  bendInputFor,
  buildProblem,
  combine,
  fail,
  ok,
  ProblemDetailsSchema,
  ProblemErrorSchema,
  validateBend,
  validateExportBends,
  validateExportProfile,
  validateHoles,
  validateProfile,
  validateSheet,
  type BendInput,
  type HoleInput,
  type HolesInput,
  type ProblemDetails,
  type ProblemError,
  type ProfileIssue,
  type ProfileIssueCode,
  type ProfileValidationInput,
  type SheetInput,
  type ValidationError,
  type ValidationResult,
} from "./validators/index.js";

export { computeKFactor, type KFactorInput } from "./k-factor.js";
