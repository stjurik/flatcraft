export { LBracketScene } from "./l-bracket-scene.js";
export { ZBracketScene } from "./z-bracket-scene.js";
export { CornerAngleScene } from "./corner-angle-scene.js";
export { WallShelfScene } from "./wall-shelf-scene.js";
export { PerforatedPanelScene } from "./perforated-panel-scene.js";
export { EnclosedShelfScene } from "./enclosed-shelf-scene.js";
export {
  buildLBracketShapeCommands,
  buildWallShelfShapeCommands,
  buildZBracketShapeCommands,
  type LBracketGeometryInputs,
  type ShapeCommand,
  type WallShelfGeometryInputs,
  type ZBracketGeometryInputs,
} from "./geometry.js";
export {
  computeCameraPlacement,
  type BoundingBoxMm,
  type CameraPlacement,
  type CameraPlacementOptions,
} from "./camera-placement.js";
export {
  computeHoleGrid,
  DEFAULT_MAX_HOLES_PREVIEW,
  type HoleGrid,
  type HoleGridCell,
  type HoleGridInput,
} from "./hole-grid.js";
