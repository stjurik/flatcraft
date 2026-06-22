/**
 * @flatcraft/types — спільні Zod-схеми та DTO між web / api / worker.
 *
 * Templates: параметричні схеми шаблонів (Phase 1.5+).
 * API / Domain / Jobs додаємо коли треба (TDD: лише після першого
 * вживача, інакше — мертвий код).
 */

export const TYPES_PACKAGE_VERSION = "0.0.0" as const;

export * from "./domain/index.js";
export * from "./products/index.js";
export * from "./templates/index.js";
