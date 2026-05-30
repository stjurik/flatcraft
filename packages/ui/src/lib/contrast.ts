/**
 * WCAG 2.1 contrast ratio between two colors.
 * Accepts `#rgb` / `#rrggbb` and `oklch(L C H)` where L ∈ [0,1].
 *
 * Pipeline for OKLCH: OKLab → LMS (Ottosson) → linear sRGB.
 * Luminance Y = 0.2126·R + 0.7152·G + 0.0722·B on linear sRGB.
 * Out-of-gamut OKLCH components are clamped to [0,1] before luminance.
 */

type LinearRgb = [number, number, number];

const HEX_RE = /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/;
const OKLCH_RE = /^oklch\(\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\)$/;

function srgbToLinear(c: number): number {
  return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
}

function parseHex(hex: string): LinearRgb {
  const body = hex.slice(1);
  const full =
    body.length === 3
      ? body
          .split("")
          .map((c) => c + c)
          .join("")
      : body;
  const r = parseInt(full.slice(0, 2), 16) / 255;
  const g = parseInt(full.slice(2, 4), 16) / 255;
  const b = parseInt(full.slice(4, 6), 16) / 255;
  return [srgbToLinear(r), srgbToLinear(g), srgbToLinear(b)];
}

function parseOklch(value: string): LinearRgb {
  const match = OKLCH_RE.exec(value);
  if (!match) throw new Error(`unsupported oklch syntax: ${value}`);
  const [, lStr, cStr, hStr] = match;
  if (!lStr || !cStr || !hStr) throw new Error(`unsupported oklch syntax: ${value}`);

  const L = parseFloat(lStr);
  const C = parseFloat(cStr);
  const Hrad = (parseFloat(hStr) * Math.PI) / 180;
  const aLab = C * Math.cos(Hrad);
  const bLab = C * Math.sin(Hrad);

  const lPrime = L + 0.3963377774 * aLab + 0.2158037573 * bLab;
  const mPrime = L - 0.1055613458 * aLab - 0.0638541728 * bLab;
  const sPrime = L - 0.0894841775 * aLab - 1.291485548 * bLab;

  const l = lPrime ** 3;
  const m = mPrime ** 3;
  const s = sPrime ** 3;

  return [
    4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
    -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s,
  ];
}

function parse(value: string): LinearRgb {
  if (HEX_RE.test(value)) return parseHex(value);
  if (value.startsWith("oklch")) return parseOklch(value);
  throw new Error(`unsupported color format: ${value}`);
}

function relativeLuminance([r, g, b]: LinearRgb): number {
  const clamp = (x: number): number => Math.max(0, Math.min(1, x));
  return 0.2126 * clamp(r) + 0.7152 * clamp(g) + 0.0722 * clamp(b);
}

export function contrastRatio(fg: string, bg: string): number {
  const Lfg = relativeLuminance(parse(fg));
  const Lbg = relativeLuminance(parse(bg));
  const [hi, lo] = Lfg > Lbg ? [Lfg, Lbg] : [Lbg, Lfg];
  return (hi + 0.05) / (lo + 0.05);
}
