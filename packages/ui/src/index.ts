/**
 * @flatcraft/ui — shadcn/ui примітиви + кастомні компоненти
 * (3D viewport, parameter-form, bom-table).
 *
 * Експорти за підмодулями (`@flatcraft/ui/3d-viewport`) — щоб споживачі
 * могли code-split'ити heavy R3F-bundle лише на маршрутах, які його
 * показують.
 */

export const UI_PACKAGE_VERSION = "0.0.0" as const;

export * from "./3d-viewport/index.js";
export * from "./components/index.js";
export { R3FErrorBoundary, R3FErrorFallback } from "./r3f-error-boundary.js";
export * from "./hooks/index.js";
export * from "./icons.js";
export * from "./lib/index.js";
export * from "./parameter-form/index.js";
export * from "./primitives/index.js";
