/**
 * Camera placement helper для 3D-viewport'ів (PR 8a, фікс камери для габаритних
 * деталей).
 *
 * Раніше кожна сцена мала inline-формулу `camDist = maxDim * <1.5..1.8>` з
 * fov=35° — це працювало для дрібних деталей, але для габаритних (enclosed_shelf
 * 1000×300, wall_shelf 1000×300, corner_angle 250×250×width=200) призводило
 * до clipping/edge-on rendering (на скриншоті користувача — лише трикутник
 * замість всієї полиці).
 *
 * Формула:
 *   - bbox-half-diagonal r = sqrt((x/2)² + (y/2)² + (z/2)²)
 *   - camDist = r / sin(fov_rad/2) * safetyFactor (1.4 default)
 *   - Position: (camDist*0.85, camDist*0.6, camDist*0.85) — кутова перспектива
 *   - Near/Far: 1 / camDist*4 — щедрий діапазон, щоб OrbitControls zoom не клипав
 *
 * Pure function, без three.js deps → тестується unit'ами і шерається між scene'ами.
 */
export interface BoundingBoxMm {
  /** Розмір по X у мм (наприклад, width_mm / length_mm). */
  readonly x: number;
  /** Розмір по Y у мм (vertical: thickness або back+depth для enclosed). */
  readonly y: number;
  /** Розмір по Z у мм (depth / width_mm для extrude). */
  readonly z: number;
}

export interface CameraPlacement {
  readonly position: readonly [number, number, number];
  readonly fov: number;
  readonly near: number;
  readonly far: number;
}

export interface CameraPlacementOptions {
  /** Vertical FOV у градусах. Default 40. */
  readonly fovDeg?: number;
  /** Запас на OrbitControls zoom-out (множник до camDist). Default 1.4. */
  readonly safetyFactor?: number;
  /**
   * Зсув кута камери у форматі [x, y, z] (нормалізовано). Default
   * [0.85, 0.6, 0.85] — кутова трьохчвертна перспектива.
   */
  readonly angle?: readonly [number, number, number];
}

const DEFAULT_FOV_DEG = 40;
const DEFAULT_SAFETY = 1.4;
const DEFAULT_ANGLE: readonly [number, number, number] = [0.85, 0.6, 0.85];

export function computeCameraPlacement(
  bbox: BoundingBoxMm,
  options: CameraPlacementOptions = {},
): CameraPlacement {
  const fovDeg = options.fovDeg ?? DEFAULT_FOV_DEG;
  const safety = options.safetyFactor ?? DEFAULT_SAFETY;
  const angle = options.angle ?? DEFAULT_ANGLE;

  const halfX = Math.max(bbox.x, 1) / 2;
  const halfY = Math.max(bbox.y, 1) / 2;
  const halfZ = Math.max(bbox.z, 1) / 2;
  const halfDiag = Math.sqrt(halfX * halfX + halfY * halfY + halfZ * halfZ);

  const fovRad = (fovDeg * Math.PI) / 180;
  const camDist = (halfDiag / Math.sin(fovRad / 2)) * safety;

  return {
    position: [angle[0] * camDist, angle[1] * camDist, angle[2] * camDist] as const,
    fov: fovDeg,
    // Near не може бути 0 (z-fighting); 1мм — безпечно для всіх габаритів.
    near: 1,
    // Far з запасом × 4 щоб OrbitControls dolly-out не клипав вузли.
    far: camDist * 4,
  };
}
