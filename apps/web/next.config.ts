import type { NextConfig } from "next";

const config: NextConfig = {
  reactStrictMode: true,
  // Workspace-пакети не публікуються — Next транспілює їх з джерела.
  transpilePackages: ["@flatcraft/ui", "@flatcraft/cad-engine", "@flatcraft/types"],
};

export default config;
