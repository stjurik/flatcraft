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

export { BendMachineSpecSchema, loadSpec, loadSpecFromFile, type BendMachineSpec } from "./spec.js";

export {
  combine,
  fail,
  ok,
  validateBend,
  validateHoles,
  validateSheet,
  type BendInput,
  type HoleInput,
  type HolesInput,
  type SheetInput,
  type ValidationError,
  type ValidationResult,
} from "./validators/index.js";
