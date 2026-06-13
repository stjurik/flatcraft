import type {
  CategoryConfig,
  ChannelConfig,
  ChannelKind,
  FullConfig,
  RoleConfig,
} from "../config/types.js";
import { channelKey, type DiffOp, type FieldChange } from "./diff.js";

// Pure-оркестратор reconcile: виконує DiffOp[] через порти (інтерфейс),
// discord.js-адаптер — у scripts/apply.ts. Тестується in-memory портами.

export interface ApplyPorts {
  createRole(config: RoleConfig): Promise<void>;
  updateRole(name: string, fields: Record<string, FieldChange>, config: RoleConfig): Promise<void>;
  reorderRoles(orderTopToBottom: string[]): Promise<void>;
  createCategory(config: CategoryConfig): Promise<void>;
  updateCategory(
    name: string,
    fields: Record<string, FieldChange>,
    config: CategoryConfig,
  ): Promise<void>;
  reorderCategories(orderTopToBottom: string[]): Promise<void>;
  createChannel(config: ChannelConfig): Promise<void>;
  updateChannel(
    target: string,
    fields: Record<string, FieldChange>,
    config: ChannelConfig,
  ): Promise<void>;
}

export interface ApplyLogger {
  info(message: string): void;
  warn(message: string): void;
  error(message: string): void;
}

export interface ApplyOutcome {
  applied: number;
  failed: { target: string; error: string }[];
  orphans: { entity: string; target: string }[];
}

const silentLogger: ApplyLogger = { info: () => {}, warn: () => {}, error: () => {} };

/**
 * Виконує ops послідовно. Інваріанти:
 * - orphan НІКОЛИ не видаляється — лише warning (рішення за людиною);
 * - помилка однієї операції не зупиняє решту (записується у failed);
 * - sleep між write-операціями — запас понад вбудований rate-limiter discord.js.
 */
export async function applyOps(
  ops: DiffOp[],
  config: FullConfig,
  ports: ApplyPorts,
  options: { sleep?: () => Promise<void>; log?: ApplyLogger } = {},
): Promise<ApplyOutcome> {
  const sleep = options.sleep ?? (() => new Promise((resolve) => setTimeout(resolve, 500)));
  const log = options.log ?? silentLogger;

  const roleByName = new Map(config.roles.map((r) => [r.name, r]));
  const categoryByName = new Map(config.categories.map((c) => [c.name, c]));
  const channelByKey = new Map(config.channels.map((c) => [channelKey(c.category, c.name), c]));

  const outcome: ApplyOutcome = { applied: 0, failed: [], orphans: [] };

  const requireConfig = <T>(map: Map<string, T>, target: string, what: string): T => {
    const found = map.get(target);
    if (found === undefined)
      throw new Error(`${what} "${target}" відсутній у config — diff застарів?`);
    return found;
  };

  for (const op of ops) {
    if (op.type === "orphan") {
      outcome.orphans.push({ entity: op.entity, target: op.target });
      log.warn(
        `ORPHAN ${op.entity} "${op.target}": є у Discord, нема у config. ` +
          `НЕ видаляю — приберіть вручну у Discord або додайте у config/*.ts.`,
      );
      continue;
    }

    try {
      switch (op.type) {
        case "create":
          if (op.entity === "role") {
            await ports.createRole(requireConfig(roleByName, op.target, "Роль"));
          } else if (op.entity === "category") {
            await ports.createCategory(requireConfig(categoryByName, op.target, "Категорія"));
          } else {
            await ports.createChannel(requireConfig(channelByKey, op.target, "Канал"));
          }
          break;
        case "update":
          if (op.entity === "role") {
            await ports.updateRole(
              op.target,
              op.fields,
              requireConfig(roleByName, op.target, "Роль"),
            );
          } else if (op.entity === "category") {
            await ports.updateCategory(
              op.target,
              op.fields,
              requireConfig(categoryByName, op.target, "Категорія"),
            );
          } else {
            await ports.updateChannel(
              op.target,
              op.fields,
              requireConfig(channelByKey, op.target, "Канал"),
            );
          }
          break;
        case "reorder":
          if (op.entity === "role") await ports.reorderRoles(op.order);
          else await ports.reorderCategories(op.order);
          break;
      }
      outcome.applied += 1;
      log.info(`OK ${op.type} ${op.entity} ${op.target}`);
      await sleep();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      outcome.failed.push({ target: op.target, error: message });
      log.error(`FAIL ${op.type} ${op.entity} ${op.target}: ${message}`);
    }
  }

  return outcome;
}

const COMMUNITY_KINDS: ChannelKind[] = ["GuildAnnouncement", "GuildForum"];

/** Які guild-фічі потрібні config'у. COMMUNITY вмикається вручну (ToS-wizard). */
export function requiredGuildFeatures(channels: ChannelConfig[]): string[] {
  return channels.some((ch) => COMMUNITY_KINDS.includes(ch.type)) ? ["COMMUNITY"] : [];
}

/**
 * Яких потрібних фіч НЕ вистачає guild'у. `guildFeatures` приймає undefined
 * захисно: частковий guild (до REST-fetch) має features=undefined — трактуємо
 * як «жодної фічі нема», щоб не впасти на `.includes`. У connect() ми форсуємо
 * REST-fetch, тож на практиці сюди приходить заповнений масив.
 */
export function missingGuildFeatures(
  channels: ChannelConfig[],
  guildFeatures: readonly string[] | undefined,
): string[] {
  const present = new Set(guildFeatures ?? []);
  return requiredGuildFeatures(channels).filter((feature) => !present.has(feature));
}
