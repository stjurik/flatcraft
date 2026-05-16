import type { FastifyPluginAsyncZod } from "fastify-type-provider-zod";
import { z } from "zod";

const HealthResponse = z.object({
  status: z.literal("ok"),
  uptime: z.number().nonnegative(),
  version: z.string(),
});

export const healthRoutes: FastifyPluginAsyncZod = async (app) => {
  app.get(
    "/health",
    {
      schema: {
        description: "Liveness probe — повертає 200 поки процес живий.",
        tags: ["meta"],
        response: { 200: HealthResponse },
      },
    },
    () => ({
      status: "ok" as const,
      uptime: process.uptime(),
      version: process.env["npm_package_version"] ?? "0.0.0",
    }),
  );
};
