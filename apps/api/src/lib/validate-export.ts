/**
 * Server-side export gate (ADR-019, Hotfix 2.10.e → 2.9.c).
 *
 * Клієнтська валідація у web — лише UX (підсвічення полів + банер). Сервер
 * ОБОВ'ЯЗКОВО перевіряє гиб проти `bend-machine-esi.yaml` ПЕРЕД постановкою
 * job/forward у cad-worker. Це інваріант CLAUDE.md §7 п.2.
 *
 * Реалізацію матричної валідації (`validateExportBends`, `buildProblem`,
 * Problem-типи) перенесено у `@flatcraft/cad-engine` (Hotfix 2.9.c, ADR-022) —
 * щоб сервер і браузер ділили ОДНУ функцію, а не дублювали матрицю. Тут лишається
 * лише node-only частина: memoized читання YAML через `@flatcraft/cad-engine/node`.
 */
import { type BendMachineSpec } from "@flatcraft/cad-engine";
import { loadSpecFromFile } from "@flatcraft/cad-engine/node";

export {
  buildProblem,
  ProblemDetailsSchema,
  ProblemErrorSchema,
  validateExportBends,
  validateExportProfile,
  type ProblemDetails,
  type ProblemError,
} from "@flatcraft/cad-engine";

/** Memoized spec — читаємо YAML один раз на процес. */
let specPromise: Promise<BendMachineSpec> | null = null;
export function getBendSpec(): Promise<BendMachineSpec> {
  specPromise ??= loadSpecFromFile();
  return specPromise;
}
