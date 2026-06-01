/**
 * Phase 2.16.b: генератор preview-PNG для каталога шаблонів.
 *
 * Запускає headless Chromium через Playwright, відвідує кожну з 5 студій
 * на локальному dev-стеку, чекає R3F-canvas, робить скріншот контейнера
 * `[data-testid="<slug>-viewport"]` (вже з border + bg-surface-sunken,
 * консистентно з карткою) і зберігає у `apps/web/public/template-previews/`.
 *
 * Use:
 *   pnpm --filter @flatcraft/web preview:generate
 *
 * Prereq: локально мають бути запущені і web (port 3000), і api (port 4000).
 * Скрипт сам жодних процесів не піднімає — це разовий ручний крок при
 * зміні geometry/colors сцен. PNG-файли йдуть у git як статичні артефакти.
 */
import { mkdir } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { chromium, type Page } from "@playwright/test";

// `import.meta.url` стабільний незалежно від cwd, з якого запускається script.
const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = join(SCRIPT_DIR, "..", "..");

interface TemplateSpec {
  readonly slug: string;
  readonly viewportTestId: string;
}

const TEMPLATES: ReadonlyArray<TemplateSpec> = [
  { slug: "l_bracket", viewportTestId: "l-bracket-viewport" },
  { slug: "z_bracket", viewportTestId: "z-bracket-viewport" },
  { slug: "corner_angle", viewportTestId: "corner-angle-viewport" },
  { slug: "wall_shelf", viewportTestId: "wall-shelf-viewport" },
  { slug: "perforated_panel", viewportTestId: "perforated-panel-viewport" },
];

const BASE_URL = process.env["PREVIEW_BASE_URL"] ?? "http://localhost:3000";
const OUTPUT_DIR = join(REPO_ROOT, "apps/web/public/template-previews");

async function captureOne(page: Page, spec: TemplateSpec): Promise<void> {
  const url = `${BASE_URL}/templates/${spec.slug}`;
  // eslint-disable-next-line no-console
  console.log(`  → ${url}`);
  await page.goto(url, { waitUntil: "domcontentloaded" });

  // canvas з'являється після hydration + dynamic(ssr:false) → даємо 15с timeout.
  await page.locator("canvas").first().waitFor({ state: "visible", timeout: 15_000 });
  // Дочекатись першого rendered кадру (R3F запускає raf одразу, але матеріали
  // компілюються асинхронно). 800ms — емпіричне значення з нашого досвіду.
  await page.waitForTimeout(800);

  const viewport = page.getByTestId(spec.viewportTestId);
  const target = join(OUTPUT_DIR, `${spec.slug}.png`);
  await viewport.screenshot({ path: target, omitBackground: false });
  // eslint-disable-next-line no-console
  console.log(`  ✓ saved ${target}`);
}

async function main(): Promise<void> {
  await mkdir(OUTPUT_DIR, { recursive: true });

  const browser = await chromium.launch({ headless: true });
  // Capture при 2× DPR — preview-image вийде ~1600×900 (для 16:9 viewport-region)
  // і красиво виглядатиме на retina у каталозі (card thumb рендериться у ~360×270).
  const context = await browser.newContext({
    viewport: { width: 1280, height: 800 },
    deviceScaleFactor: 2,
    // Force `prefers-reduced-motion: no-preference` — щоб OrbitControls не вимикався.
    reducedMotion: "no-preference",
  });
  const page = await context.newPage();

  try {
    for (const spec of TEMPLATES) {
      await captureOne(page, spec);
    }
  } finally {
    await browser.close();
  }

  // eslint-disable-next-line no-console
  console.log(`Done. ${TEMPLATES.length} previews → ${OUTPUT_DIR}`);
}

main().catch((err: unknown) => {
  console.error(err);
  process.exit(1);
});
