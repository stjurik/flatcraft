import { expect, test } from "@playwright/test";

const TEMPLATES: ReadonlyArray<{ slug: string; studioTestId: string; viewportTestId: string }> = [
  { slug: "l_bracket", studioTestId: "l-bracket-studio", viewportTestId: "l-bracket-viewport" },
  { slug: "z_bracket", studioTestId: "z-bracket-studio", viewportTestId: "z-bracket-viewport" },
  {
    slug: "corner_angle",
    studioTestId: "corner-angle-studio",
    viewportTestId: "corner-angle-viewport",
  },
  { slug: "wall_shelf", studioTestId: "wall-shelf-studio", viewportTestId: "wall-shelf-viewport" },
  {
    slug: "perforated_panel",
    studioTestId: "perforated-panel-studio",
    viewportTestId: "perforated-panel-viewport",
  },
];

const MOBILE = { width: 360, height: 640 } as const;

test.describe("Phase 2.14.a — mobile studio (360×640)", () => {
  test.use({ viewport: MOBILE });

  for (const { slug, studioTestId, viewportTestId } of TEMPLATES) {
    test(`${slug}: studio + viewport рендеряться, anchor видимий, console-clean`, async ({
      page,
    }) => {
      const errors: string[] = [];
      page.on("console", (msg) => {
        if (msg.type() === "error") errors.push(msg.text());
      });

      await page.goto(`/templates/${slug}`);
      await expect(page.getByTestId(studioTestId)).toBeVisible();
      await expect(page.getByTestId(viewportTestId)).toBeVisible();
      // 3D canvas рендериться нижче (lazy-load → даємо час).
      await page.locator("canvas").first().waitFor({ state: "visible", timeout: 15_000 });

      // Anchor видимий лише у вертикальному layout (lg:hidden).
      const anchor = page.getByTestId("studio-preview-anchor");
      await expect(anchor).toBeVisible();
      await expect(anchor).toHaveAttribute("href", "#studio-viewport");

      expect(errors, errors.join("\n")).toEqual([]);
    });
  }

  test("l_bracket: anchor скролить до canvas-секції", async ({ page }) => {
    await page.goto("/templates/l_bracket");
    await page.getByTestId("studio-preview-anchor").click();
    // Після scroll viewport-секція має бути у viewport (top < vh).
    const top = await page
      .locator("#studio-viewport")
      .evaluate((el) => el.getBoundingClientRect().top);
    expect(top).toBeLessThan(MOBILE.height);
  });

  test("l_bracket: tap-targets material+thickness selects ≥ 44×44px", async ({ page }) => {
    await page.goto("/templates/l_bracket");
    const ids = ["select-material_code", "select-thickness_mm"];
    for (const id of ids) {
      const dim = await page
        .getByTestId(id)
        .evaluate((el: HTMLElement) => ({ w: el.offsetWidth, h: el.offsetHeight }));
      expect(dim.w, `${id} width`).toBeGreaterThanOrEqual(44);
      expect(dim.h, `${id} height`).toBeGreaterThanOrEqual(44);
    }
  });

  test("Export button на mobile ≥44px (інваріант WCAG 2.5.5)", async ({ page }) => {
    await page.goto("/templates/l_bracket");
    const dim = await page
      .getByTestId("export-button")
      .evaluate((el: HTMLElement) => ({ w: el.offsetWidth, h: el.offsetHeight }));
    expect(dim.w).toBeGreaterThanOrEqual(44);
    expect(dim.h).toBeGreaterThanOrEqual(44);
  });
});

test.describe("Phase 2.14.a — desktop studio (1280×800)", () => {
  test.use({ viewport: { width: 1280, height: 800 } });

  test("anchor прихований на lg+ (lg:hidden)", async ({ page }) => {
    await page.goto("/templates/l_bracket");
    await expect(page.getByTestId("studio-preview-anchor")).toBeHidden();
  });
});
