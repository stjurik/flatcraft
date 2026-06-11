import {
  ChannelType,
  OverwriteType,
  type CategoryChannel,
  type Guild,
  type GuildChannelCreateOptions,
  type OverwriteResolvable,
} from "discord.js";

import { CATEGORIES } from "../config/categories.js";
import { CHANNELS } from "../config/channels.js";
import { ROLES } from "../config/roles.js";
import {
  validateConfigIntegrity,
  type ChannelKind,
  type PermissionOverwriteConfig,
} from "../config/types.js";
import { applyOps, requiredGuildFeatures, type ApplyPorts } from "../lib/apply.js";
import { connect } from "../lib/client.js";
import { diffAll } from "../lib/diff.js";
import { fetchActualState } from "../lib/fetch-state.js";
import { formatOps } from "../lib/format-ops.js";
import { flagsToBitfield } from "../lib/permissions.js";

// Reconcile: config → Discord. Запускається ЛИШЕ вручну з машини
// (pnpm discord:apply) — ніколи у CI (ADR-023). Orphan'и не видаляються.

const CHANNEL_TYPE = {
  GuildText: ChannelType.GuildText,
  GuildAnnouncement: ChannelType.GuildAnnouncement,
  GuildForum: ChannelType.GuildForum,
  GuildVoice: ChannelType.GuildVoice,
} as const satisfies Record<ChannelKind, ChannelType>;

function buildPorts(guild: Guild): ApplyPorts {
  const roleId = (name: string): string => {
    if (name === "@everyone") return guild.id;
    const role = guild.roles.cache.find((r) => r.name === name);
    if (role === undefined) throw new Error(`Роль "${name}" не знайдена у guild (ще не створена?)`);
    return role.id;
  };

  const toOverwrites = (configs: PermissionOverwriteConfig[]): OverwriteResolvable[] =>
    configs.map((ow) => ({
      id: roleId(ow.role),
      type: OverwriteType.Role,
      allow: flagsToBitfield(ow.allow),
      deny: flagsToBitfield(ow.deny),
    }));

  const categoryByName = (name: string): CategoryChannel => {
    const found = guild.channels.cache.find(
      (ch) => ch.type === ChannelType.GuildCategory && ch.name === name,
    );
    if (found === undefined) throw new Error(`Категорія "${name}" не знайдена у guild`);
    return found as CategoryChannel;
  };

  const channelByTarget = (target: string) => {
    // target = "<категорія>/<ім'я>" (див. channelKey у lib/diff.ts)
    const slash = target.indexOf("/");
    const categoryName = target.slice(0, slash);
    const channelName = target.slice(slash + 1);
    const parent = categoryByName(categoryName);
    const found = guild.channels.cache.find(
      (ch) => ch.parentId === parent.id && ch.name === channelName,
    );
    if (found === undefined) throw new Error(`Канал "${target}" не знайдений у guild`);
    return found;
  };

  return {
    async createRole(config) {
      await guild.roles.create({
        name: config.name,
        color: config.color,
        hoist: config.hoist,
        permissions: flagsToBitfield(config.permissions),
        mentionable: false,
      });
    },
    async updateRole(name, _fields, config) {
      await guild.roles.cache.get(roleId(name))!.edit({
        color: config.color,
        hoist: config.hoist,
        permissions: flagsToBitfield(config.permissions),
      });
    },
    async reorderRoles(orderTopToBottom) {
      // Бот може рухати лише ролі НИЖЧЕ власної найвищої — ставимо desired
      // порядок знизу вгору; недосяжні позиції Discord мовчки обмежить.
      const positions = orderTopToBottom
        .map((name, index) => ({ role: roleId(name), position: orderTopToBottom.length - index }))
        .reverse();
      await guild.roles.setPositions(positions);
    },
    async createCategory(config) {
      await guild.channels.create({
        name: config.name,
        type: ChannelType.GuildCategory,
        position: config.position,
        permissionOverwrites: toOverwrites(config.permissionOverwrites),
      });
    },
    async updateCategory(name, _fields, config) {
      await categoryByName(name).permissionOverwrites.set(
        toOverwrites(config.permissionOverwrites),
      );
    },
    async reorderCategories(orderTopToBottom) {
      for (const [index, name] of orderTopToBottom.entries()) {
        await categoryByName(name).setPosition(index);
      }
    },
    async createChannel(config) {
      const options: GuildChannelCreateOptions = {
        name: config.name,
        type: CHANNEL_TYPE[config.type],
        parent: categoryByName(config.category).id,
        ...(config.topic === undefined ? {} : { topic: config.topic }),
        ...(config.tags === undefined
          ? {}
          : { availableTags: config.tags.map((tag) => ({ name: tag })) }),
        ...(config.permissionOverwrites.length === 0
          ? {}
          : { permissionOverwrites: toOverwrites(config.permissionOverwrites) }),
      };
      await guild.channels.create(options);
    },
    async updateChannel(target, fields, config) {
      const channel = channelByTarget(target);
      if ("type" in fields) {
        throw new Error(
          `Зміна типу каналу ${target} (${JSON.stringify(fields["type"])}) не підтримується ` +
            `Discord API — перестворіть канал вручну.`,
        );
      }
      await channel.edit({
        ...(fields["topic"] === undefined ? {} : { topic: config.topic ?? "" }),
        ...(fields["tags"] === undefined || config.tags === undefined
          ? {}
          : { availableTags: config.tags.map((tag) => ({ name: tag })) }),
        ...(fields["permissionOverwrites"] === undefined
          ? {}
          : { permissionOverwrites: toOverwrites(config.permissionOverwrites) }),
      });
    },
  };
}

async function main(): Promise<void> {
  const config = { roles: ROLES, categories: CATEGORIES, channels: CHANNELS };
  const integrityErrors = validateConfigIntegrity(config);
  if (integrityErrors.length > 0) {
    for (const err of integrityErrors) console.error(`CONFIG: ${err}`);
    process.exitCode = 1;
    return;
  }

  const { client, guild } = await connect();
  try {
    // Preflight: GuildAnnouncement/GuildForum вимагають Community-фічі,
    // яку вмикають лише вручну (ToS-wizard, MANUAL_SETUP.md крок 2).
    const missing = requiredGuildFeatures(config.channels).filter(
      (feature) => !guild.features.includes(feature as never),
    );
    if (missing.length > 0) {
      console.error(
        `Guild не має фіч: ${missing.join(", ")}. Увімкніть Community у ` +
          `Server Settings → Enable Community (MANUAL_SETUP.md, крок 2) і повторіть.`,
      );
      process.exitCode = 1;
      return;
    }

    const stateBefore = await fetchActualState(guild);
    const ops = diffAll(stateBefore, config);
    console.info(formatOps(ops));
    if (ops.length === 0) return;

    const outcome = await applyOps(ops, config, buildPorts(guild), {
      log: { info: console.info, warn: console.warn, error: console.error },
    });

    console.info(
      `\nЗастосовано: ${outcome.applied}, помилок: ${outcome.failed.length}, ` +
        `orphan-попереджень: ${outcome.orphans.length}.`,
    );
    if (outcome.failed.length > 0) process.exitCode = 1;
  } finally {
    await client.destroy();
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
