import { ChannelType } from "discord.js";

import type { ChannelKind } from "../config/types.js";
import type { ActualCategory, ActualChannel, ActualOverwrite, ActualState } from "./diff.js";
import { bitfieldToFlags } from "./permissions.js";

// Duck-typed підмножини discord.js об'єктів: pure-мапінг тестується
// in-memory fake-guild'ом без моків. scripts/ передають сюди реальні
// Role/GuildChannel — структурно сумісні.

export interface RoleLike {
  id: string;
  name: string;
  color: number;
  hoist: boolean;
  position: number;
  managed: boolean;
  permissions: { bitfield: bigint };
}

export interface OverwriteLike {
  id: string;
  type: number; // 0 = role, 1 = member
  allow: { bitfield: bigint };
  deny: { bitfield: bigint };
}

export interface ChannelLike {
  id: string;
  name: string;
  type: number; // discord.js ChannelType
  parentId: string | null;
  rawPosition: number;
  topic?: string | null;
  availableTags?: { name: string }[];
  overwrites: OverwriteLike[];
}

const KIND_BY_TYPE = new Map<number, ChannelKind>([
  [ChannelType.GuildText, "GuildText"],
  [ChannelType.GuildAnnouncement, "GuildAnnouncement"],
  [ChannelType.GuildForum, "GuildForum"],
  [ChannelType.GuildVoice, "GuildVoice"],
]);

const OVERWRITE_ROLE = 0;

export function mapGuildState(input: {
  everyoneId: string;
  roles: RoleLike[];
  channels: ChannelLike[];
}): ActualState {
  const roleNameById = new Map(input.roles.map((r) => [r.id, r.name]));

  const mapOverwrites = (overwrites: OverwriteLike[]): ActualOverwrite[] =>
    overwrites
      .filter((ow) => ow.type === OVERWRITE_ROLE)
      .map((ow) => ({
        role: ow.id === input.everyoneId ? "@everyone" : (roleNameById.get(ow.id) ?? ow.id),
        allow: bitfieldToFlags(ow.allow.bitfield),
        deny: bitfieldToFlags(ow.deny.bitfield),
      }))
      .sort((a, b) => a.role.localeCompare(b.role));

  const roles = input.roles
    .map((r) => ({
      id: r.id,
      name: r.name,
      color: r.color,
      hoist: r.hoist,
      permissions: bitfieldToFlags(r.permissions.bitfield),
      position: r.position,
      managed: r.managed,
    }))
    .sort((a, b) => b.position - a.position || a.name.localeCompare(b.name));

  const categoryChannels = input.channels
    .filter((ch) => ch.type === (ChannelType.GuildCategory as number))
    .sort((a, b) => a.rawPosition - b.rawPosition || a.name.localeCompare(b.name));

  const categories: ActualCategory[] = categoryChannels.map((ch) => ({
    id: ch.id,
    name: ch.name,
    position: ch.rawPosition,
    permissionOverwrites: mapOverwrites(ch.overwrites),
  }));

  const categoryNameById = new Map(categoryChannels.map((ch) => [ch.id, ch.name]));

  const channels: ActualChannel[] = input.channels
    .filter((ch) => ch.type !== (ChannelType.GuildCategory as number))
    .sort((a, b) => a.rawPosition - b.rawPosition || a.name.localeCompare(b.name))
    .map((ch) => ({
      id: ch.id,
      name: ch.name,
      type: KIND_BY_TYPE.get(ch.type) ?? "other",
      category: ch.parentId === null ? null : (categoryNameById.get(ch.parentId) ?? null),
      topic: ch.topic ?? null,
      ...(ch.availableTags === undefined ? {} : { tags: ch.availableTags.map((t) => t.name) }),
      permissionOverwrites: mapOverwrites(ch.overwrites),
    }));

  return { roles, categories, channels };
}
