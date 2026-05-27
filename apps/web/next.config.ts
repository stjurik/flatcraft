import type { NextConfig } from "next";

const config: NextConfig = {
  reactStrictMode: true,
  // Standalone output — мінімальний runtime з лише потрібними node_modules,
  // потрібен для production-Dockerfile (apps/web → docker image).
  // У dev-режимі ігнорується.
  output: "standalone",
  // Workspace-пакети не публікуються — Next транспілює їх з джерела.
  transpilePackages: ["@flatcraft/ui", "@flatcraft/cad-engine", "@flatcraft/types"],
  webpack: (cfg) => {
    // verbatimModuleSyntax + module:ESNext у tsconfig.base змушує писати
    // `import "./foo.js"` навіть для TS-файлів. Webpack за замовчуванням
    // шукає `.js` і не знаходить — додаємо extensionAlias щоб резолвити
    // `.js` → реальні `.ts`/`.tsx` у workspace-пакетах.
    cfg.resolve = cfg.resolve ?? {};
    cfg.resolve.extensionAlias = {
      ...cfg.resolve.extensionAlias,
      ".js": [".ts", ".tsx", ".js"],
      ".mjs": [".mts", ".mjs"],
    };
    return cfg;
  },
};

export default config;
