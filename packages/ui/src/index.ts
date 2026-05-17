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
export * from "./parameter-form/index.js";
