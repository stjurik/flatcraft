/**
 * React-free import-graph invariant (ADR-033 §1, §5; docs/12_TEMPLATE_CONTRACT.md
 * §3.5). `apps/api` — Fastify/Node.js без DOM; `@flatcraft/templates`
 * (react-free data-пакет) не сміє протягнути `react`/`react-dom` у серверний
 * бандл, інакше startup-час і bundle-size ростуть без причини.
 *
 * Реалізація: бандлимо `src/registry.ts` через esbuild з `metafile: true`,
 * перевіряємо, що жоден вхідний модуль метафайлу не резолвиться у
 * `react`/`react-dom` пакет.
 */
import path from "node:path";
import { fileURLToPath } from "node:url";

import * as esbuild from "esbuild";
import { describe, expect, test } from "vitest";

const HERE = path.dirname(fileURLToPath(import.meta.url));

describe("registry import у apps/api", () => {
  test("НЕ тягне react/react-dom у бандл", async () => {
    const result = await esbuild.build({
      entryPoints: [path.join(HERE, "registry.ts")],
      bundle: true,
      write: false,
      platform: "node",
      metafile: true,
      logLevel: "silent",
    });

    const inputPaths = Object.keys(result.metafile.inputs);
    const reactModules = inputPaths.filter((p) => /node_modules\/(react|react-dom)\//.test(p));

    expect(reactModules).toEqual([]);
  });
});
