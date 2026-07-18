import { expect, test } from "@playwright/test";

import { SITE_URL } from "../../src/lib/site-url";

// ADR-037 — Etap A: лендінг/about/soon/каталог/картки/деталі шаблону
// (breadcrumb-only)/OG. Студії (усередині templates/[slug], products/[slug])
// СВІДОМО лишаються українськими (§5) — тести цього файлу цього не
// перевіряють як помилку.

test.describe("i18n Etap A — EN дзеркала (ADR-037)", () => {
  test("/en — лендінг рендериться англійською", async ({ page }) => {
    await page.goto("/en");
    await expect(page.getByTestId("hero-headline")).toContainText(
      "Sheet-metal drawings in 60 seconds",
    );
    const cta = page.getByTestId("hero-cta");
    await expect(cta).toHaveAttribute("href", "/en/templates");
    await expect(page.getByTestId("step-card-0")).toContainText("Pick a template");
  });

  test("/en/about — рендериться англійською", async ({ page }) => {
    await page.goto("/en/about");
    await expect(page.getByTestId("about-hero")).toContainText("Sheet-metal drawings");
    await expect(page.getByTestId("about-zsu")).toContainText("Support Ukraine's defense");
  });

  test("/en/soon — рендериться англійською, «← Back home» веде на /en", async ({ page }) => {
    await page.goto("/en/soon");
    await expect(page.getByRole("heading", { name: "Planned page" })).toBeVisible();
    const back = page.getByRole("link", { name: "← Back home" });
    await expect(back).toHaveAttribute("href", "/en");
  });

  test("/en/templates — картки з EN-назвами (nameEn з DB), CTA веде на /en/templates/:slug", async ({
    page,
  }) => {
    await page.goto("/en/templates?tab=parts");
    await expect(page.getByTestId("templates-page-title")).toHaveText("Catalog");
    const card = page.locator('[data-testid="template-card"][data-slug="l_bracket"]');
    await expect(card).toContainText("L-bracket");
    const cta = card.getByTestId("template-card-cta");
    await expect(cta).toContainText("Configure");
    await expect(cta).toHaveAttribute("href", "/en/templates/l_bracket");
  });

  test("/en/templates/l_bracket — EN breadcrumb + title; студія лишається (ADR-037 §5)", async ({
    page,
  }) => {
    await page.goto("/en/templates/l_bracket");
    await expect(page.getByRole("link", { name: "← All templates" })).toHaveAttribute(
      "href",
      "/en/templates",
    );
    await expect(page.getByTestId("template-detail-title")).toHaveText("L-bracket");
    // Студія (AutoForm-лейбли) НЕ перекладена цим PR — свідомий Etap A-ліміт.
    await expect(page.getByTestId("export-button")).toBeVisible();
  });

  test("uk /templates/l_bracket лишається українською (регресія не внесена)", async ({ page }) => {
    await page.goto("/templates/l_bracket");
    await expect(page.getByTestId("template-detail-title")).toHaveText("L-кронштейн");
    await expect(page.getByRole("link", { name: "← Усі шаблони" })).toBeVisible();
  });

  test("/en/opengraph-image — PNG 1200×630 (окремий EN-варіант)", async ({ request }) => {
    const res = await request.get("/en/opengraph-image");
    expect(res.status()).toBe(200);
    expect(res.headers()["content-type"]).toMatch(/^image\/png/);
    const body = await res.body();
    expect(body.subarray(0, 8)).toEqual(
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    );
  });

  test("LocaleSwitcher: uk→en і назад, зберігає поточний шаблон", async ({ page }) => {
    await page.goto("/templates/l_bracket");
    const switcher = page.getByTestId("locale-switcher");
    await expect(switcher).toHaveAttribute("aria-label", "Switch to English");
    await switcher.click();
    await expect(page).toHaveURL(/\/en\/templates\/l_bracket$/);
    await expect(page.getByTestId("locale-switcher")).toHaveAttribute(
      "aria-label",
      "Switch to Ukrainian",
    );
    await page.getByTestId("locale-switcher").click();
    await expect(page).toHaveURL(/\/templates\/l_bracket$/);
  });

  test("LocaleSwitcher НЕ рендериться поза дзеркаленим набором (/privacy)", async ({ page }) => {
    await page.goto("/privacy");
    await expect(page.getByTestId("locale-switcher")).toHaveCount(0);
  });

  test("LocaleSwitcher tap-target ≥ 44×44px (WCAG 2.5.5)", async ({ page }) => {
    await page.goto("/");
    const dim = await page
      .getByTestId("locale-switcher")
      .evaluate((el: HTMLElement) => ({ w: el.offsetWidth, h: el.offsetHeight }));
    expect(dim.w).toBeGreaterThanOrEqual(44);
    expect(dim.h).toBeGreaterThanOrEqual(44);
  });

  test("middleware: uk-локаль (playwright.config default) НЕ редіректить /", async ({ page }) => {
    await page.goto("/");
    await expect(page).toHaveURL(/\/$/);
    await expect(page.getByTestId("hero-headline")).toContainText("Креслення листового металу");
  });

  test.describe("middleware — Accept-Language en-US override", () => {
    // Ізольовано від playwright.config.ts use.locale="uk-UA" (захист наявних
    // uk-тестів від auto-редіректу, ADR-037 §3) — саме тут перевіряємо
    // протилежний випадок explicit-контекстом через nested describe (baseURL
    // успадковується через `page`-фікстуру, на відміну від ручного
    // `browser.newContext()`).
    test.use({ locale: "en-US" });

    test("перший візит на / редіректить → /en + ставить hart_locale cookie", async ({
      page,
      context,
    }) => {
      await page.goto("/");
      await expect(page).toHaveURL(/\/en$/);
      await expect(page.getByTestId("hero-headline")).toContainText("Sheet-metal drawings");
      const cookies = await context.cookies();
      expect(cookies.find((c) => c.name === "hart_locale")?.value).toBe("en");
    });

    test("після редіректу cookie не редіректить повторно прямий візит uk /about", async ({
      page,
    }) => {
      await page.goto("/");
      await expect(page).toHaveURL(/\/en$/);
      // Cookie вже виставлена → прямий візит uk /about НЕ редіректиться.
      await page.goto("/about");
      await expect(page).toHaveURL(/\/about$/);
      await expect(page.getByTestId("about-hero")).toContainText("Креслення листового металу");
    });
  });

  const VIEWPORTS = [
    { name: "mobile-360", width: 360, height: 640 },
    { name: "desktop-1280", width: 1280, height: 800 },
  ] as const;

  for (const { name, width, height } of VIEWPORTS) {
    test(`/en console-clean на ${name}`, async ({ page }) => {
      const errors: string[] = [];
      page.on("console", (msg) => {
        if (msg.type() === "error") errors.push(msg.text());
      });
      await page.setViewportSize({ width, height });
      await page.goto("/en");
      await expect(page.getByTestId("hero-headline")).toBeVisible();
      await page.locator("canvas").first().waitFor({ state: "visible", timeout: 15_000 });
      expect(errors, errors.join("\n")).toEqual([]);
    });
  }
});

// ADR-037 §7 follow-up (Master Run 8 Стадія 3 зауваження зони D) — hreflang
// reciprocal alternates. 3 сторінки покривають усі 3 routing-патерни:
// статична дзеркалена (/), динамічна дзеркалена (/templates/[slug]) і
// суфіксна легасі-схема (/privacy + /privacy/en). Кожна — в обох локалях
// (3 × 2 = 6 тестів).
test.describe("hreflang alternates (ADR-037 §7)", () => {
  // Next.js резолвить bare "/" проти metadataBase БЕЗ trailing slash
  // (href="https://hart.crimea.ua", не ".../"), тому порівнюємо точним
  // абсолютним URL (через той самий SITE_URL, що й код), а не суфіксним
  // regex — уникає і цього edge-case, і випадкових substring-збігів.
  function absoluteUrl(path: string): string {
    return path === "/" ? SITE_URL : `${SITE_URL}${path}`;
  }

  const PAGES = [
    { uk: "/", en: "/en" },
    { uk: "/templates/l_bracket", en: "/en/templates/l_bracket" },
    { uk: "/privacy", en: "/privacy/en" },
  ] as const;

  for (const { uk, en } of PAGES) {
    for (const [label, ownPath] of [
      ["uk", uk],
      ["en", en],
    ] as const) {
      test(`${uk} ⇄ ${en} — <link rel="alternate"> на ${label}-версії`, async ({ page }) => {
        await page.goto(ownPath);
        await expect(page.locator('link[rel="alternate"][hreflang="uk"]')).toHaveAttribute(
          "href",
          absoluteUrl(uk),
        );
        await expect(page.locator('link[rel="alternate"][hreflang="en"]')).toHaveAttribute(
          "href",
          absoluteUrl(en),
        );
        await expect(page.locator('link[rel="alternate"][hreflang="x-default"]')).toHaveAttribute(
          "href",
          absoluteUrl(uk),
        );
        await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
          "href",
          absoluteUrl(ownPath),
        );
      });
    }
  }
});

test.describe("sitemap.xml (ADR-037 §7 follow-up)", () => {
  test("віддає XML з uk+en URL і reciprocal alternates для статичної і динамічної сторінки", async ({
    request,
  }) => {
    const res = await request.get("/sitemap.xml");
    expect(res.status()).toBe(200);
    expect(res.headers()["content-type"]).toMatch(/xml/);
    const body = await res.text();

    // Статична дзеркалена пара — обидва URL присутні як окремі <url>-записи.
    expect(body).toContain(`<loc>${SITE_URL}/templates</loc>`);
    expect(body).toContain(`<loc>${SITE_URL}/en/templates</loc>`);
    // Динамічна пара (slug з реального seed) — доводить, що API-виклик у
    // sitemap() дійсно резолвиться, а не мовчки повертає порожній список.
    expect(body).toContain(`<loc>${SITE_URL}/templates/l_bracket</loc>`);
    expect(body).toContain(`<loc>${SITE_URL}/en/templates/l_bracket</loc>`);
    // Reciprocal hreflang на рівні sitemap (не лише <link> на сторінці).
    expect(body).toContain(`hreflang="en" href="${SITE_URL}/en/templates/l_bracket"`);
    expect(body).toContain(`hreflang="uk" href="${SITE_URL}/templates/l_bracket"`);
    // /f/[exportId] — свідомо поза scope (private noindex QR-посилання).
    expect(body).not.toContain("/f/");
  });
});
