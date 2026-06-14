import type { Guild } from "discord.js";

import type { ActualState } from "./diff.js";
import { mapGuildState, type ChannelLike } from "./state.js";

/** Fetch живого стану guild → plain ActualState (I/O-обгортка над pure mapGuildState). */
export async function fetchActualState(guild: Guild): Promise<ActualState> {
  const roles = await guild.roles.fetch();
  const channels = await guild.channels.fetch();

  const channelLikes: ChannelLike[] = [...channels.values()]
    .filter((ch) => ch !== null)
    .map((ch) => ({
      id: ch.id,
      name: ch.name,
      type: ch.type,
      parentId: ch.parentId,
      rawPosition: "rawPosition" in ch ? ch.rawPosition : 0,
      topic: "topic" in ch ? ch.topic : null,
      ...("availableTags" in ch
        ? { availableTags: ch.availableTags.map((t) => ({ name: t.name })) }
        : {}),
      overwrites:
        "permissionOverwrites" in ch
          ? [...ch.permissionOverwrites.cache.values()].map((ow) => ({
              id: ow.id,
              type: ow.type,
              allow: { bitfield: ow.allow.bitfield },
              deny: { bitfield: ow.deny.bitfield },
            }))
          : [],
    }));

  return mapGuildState({
    everyoneId: guild.id,
    roles: [...roles.values()].map((r) => ({
      id: r.id,
      name: r.name,
      color: r.color,
      hoist: r.hoist,
      position: r.position,
      managed: r.managed,
      permissions: { bitfield: r.permissions.bitfield },
    })),
    channels: channelLikes,
  });
}
