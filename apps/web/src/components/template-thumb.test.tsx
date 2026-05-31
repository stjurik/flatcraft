import { renderToString } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { TemplateThumb } from "./template-thumb";

describe("TemplateThumb — slug → schematic SVG", () => {
  const KNOWN_SLUGS = [
    "l_bracket",
    "z_bracket",
    "corner_angle",
    "wall_shelf",
    "perforated_panel",
  ] as const;

  for (const slug of KNOWN_SLUGS) {
    it(`${slug} → SVG з testId template-thumb-${slug}`, () => {
      const html = renderToString(<TemplateThumb slug={slug} />);
      expect(html).toContain(`data-testid="template-thumb-${slug}"`);
      expect(html).toContain("<svg");
      // Усі схеми використовують currentColor — щоб тон керувався text-* класом
      // з контексту картки (group-hover, etc.).
      expect(html).toContain('stroke="currentColor"');
    });
  }

  it("невідомий slug → fallback з testId template-thumb-fallback", () => {
    const html = renderToString(<TemplateThumb slug="totally_unknown_slug_xyz" />);
    expect(html).toContain('data-testid="template-thumb-fallback"');
    expect(html).toContain("<svg");
  });
});
