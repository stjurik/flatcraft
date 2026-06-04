/**
 * Rate-limit plugin (Phase X.1 A, ADR-020).
 *
 * Soft-launch без auth: захист від abuse — лише IP-based (толерантний до NAT).
 *
 * ВАЖЛИВО — `global: false`. Глобальний per-IP ліміт несумісний із SSR: web
 * (Next.js) робить server-side fetch до API (`/templates`, `/materials`) з ОДНІЄЇ
 * IP-адреси контейнера. Глобальний ліміт миттєво throttl'ив би усі SSR-запити
 * усіх користувачів під спільним ключем (саме це й зловило CI — 429 на
 * `/materials` під час e2e). Тому ліміт вмикається ТОЧКОВО, лише на browser-
 * direct маршрутах (POST /exports), через `config.rateLimit`. Глобальний
 * flood-захист живе на рівні Cloudflare WAF (ADR-020), де ключем є реальна
 * клієнтська IP, а не web-контейнер.
 *
 * - POST /exports: 30 експортів/год/IP + burst-ban після 50 (через `ban`).
 *   Аргумент за 30/год: DIY-користувач за день не зробить >30 експортів;
 *   офіс за NAT з ~10 людьми теж укладеться; бот блокується після 30 спроб.
 *   Цей маршрут б'ється з браузера напряму, тож req.ip = реальна клієнтська IP
 *   (у prod через trustProxy + X-Forwarded-For від Caddy/CF).
 */
import rateLimit, { type RateLimitOptions, type RateLimitPluginOptions } from "@fastify/rate-limit";
import type { FastifyInstance } from "fastify";
import fp from "fastify-plugin";

/**
 * Опції реєстрації плагіна. `global: false` — жоден маршрут не лімітується за
 * замовчуванням; ліміт застосовується лише там, де є `config.rateLimit`.
 * `max`/`timeWindow` — лише дефолти для opted-in маршрутів без власних чисел.
 */
export const RATE_LIMIT_PLUGIN_OPTIONS: RateLimitPluginOptions = {
  global: false,
  max: 100,
  timeWindow: "1 minute",
};

/**
 * RFC 9457 problem details для перевищення export-ліміту. `ttl` — мс до
 * скидання вікна (з контексту плагіна), конвертуємо у хвилини для підказки.
 */
function exportRateLimitProblem(_req: unknown, context: { ttl: number; ban?: boolean }) {
  const minutes = Math.max(1, Math.ceil(context.ttl / 60_000));
  const banned = context.ban === true;
  return {
    type: "https://flatcraft.io/errors/rate-limit",
    title: banned ? "Temporarily banned" : "Rate limit exceeded",
    status: banned ? 403 : 429,
    detail: banned
      ? `Забагато запитів з вашої IP-адреси. Доступ тимчасово обмежено. Спробуйте через ${minutes} хв.`
      : `Перевищено ліміт 30 експортів на годину з вашої IP-адреси. Спробуйте через ${minutes} хв.`,
    instance: "/exports",
  };
}

/**
 * Per-route конфіг для POST /exports. Експортується окремо, щоб:
 *  (1) unit-тест перевірив числа (max=30, window=1h, ban=50);
 *  (2) маршрут підключив його через `config.rateLimit`.
 */
export const EXPORT_RATE_LIMIT: RateLimitOptions = {
  max: 30,
  timeWindow: "1 hour",
  // Burst-protection: після 50 запитів у вікні — тимчасовий бан (403).
  ban: 50,
  keyGenerator: (req) => req.ip,
  errorResponseBuilder: exportRateLimitProblem,
};

async function rateLimitPlugin(app: FastifyInstance): Promise<void> {
  await app.register(rateLimit, RATE_LIMIT_PLUGIN_OPTIONS);
}

/**
 * fastify-plugin → не інкапсулюється, тож per-route `config.rateLimit`
 * (зокрема у routes/exports.ts) бачить зареєстрований плагін.
 */
export default fp(rateLimitPlugin, { name: "rate-limit" });
