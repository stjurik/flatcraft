/**
 * session_hash для телеметрії (ADR-032 п.6 / docs/11_OBSERVABILITY.md §7).
 *
 * `session_hash = sha256(ip + добовий salt)`, обрізаний. **Сирий IP НЕ
 * зберігається** (GDPR). Salt ротується щодоби (in-memory; регенерується на зміні
 * UTC-дати й на рестарті процесу) — зшити сесії одного користувача між добами
 * неможливо. Мета — агрегатний сигнал (унікальні сесії/день), не стеження.
 */
import { createHash, randomBytes } from "node:crypto";

function utcDay(now: Date): string {
  return now.toISOString().slice(0, 10);
}

let saltDay = "";
let saltValue = "";

/** Поточний добовий salt; регенерується на зміні UTC-дати. */
export function dailySalt(now: Date = new Date()): string {
  const day = utcDay(now);
  if (day !== saltDay) {
    saltDay = day;
    saltValue = randomBytes(16).toString("hex");
  }
  return saltValue;
}

/**
 * Непереслідуваний `session_hash` з IP і salt'а. Pure за `(ip, salt)`. Порожній
 * IP → `null` (нема з чого рахувати; сам IP ніколи не потрапляє у вихід).
 */
export function sessionHash(ip: string | undefined, salt: string = dailySalt()): string | null {
  if (!ip) return null;
  return createHash("sha256").update(`${ip}:${salt}`).digest("hex").slice(0, 32);
}
