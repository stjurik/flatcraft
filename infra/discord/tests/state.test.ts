import { ChannelType, PermissionFlagsBits } from "discord.js";
import { describe, expect, it } from "vitest";

import { mapGuildState, type ChannelLike, type RoleLike } from "../lib/state.js";

// In-memory fake guild — plain-об'єкти, структурно сумісні з discord.js.

const EVERYONE_ID = "guild-1";

const fakeRoles: RoleLike[] = [
  {
    id: EVERYONE_ID,
    name: "@everyone",
    color: 0,
    hoist: false,
    position: 0,
    managed: false,
    permissions: { bitfield: PermissionFlagsBits.SendMessages },
  },
  {
    id: "r-founder",
    name: "🔴 Founder",
    color: 0xed4245,
    hoist: true,
    position: 2,
    managed: false,
    permissions: { bitfield: PermissionFlagsBits.Administrator },
  },
  {
    id: "r-bot",
    name: "hart-iac",
    color: 0,
    hoist: false,
    position: 3,
    managed: true,
    permissions: { bitfield: PermissionFlagsBits.Administrator },
  },
];

const fakeChannels: ChannelLike[] = [
  {
    id: "cat-info",
    name: "📋 ІНФОРМАЦІЯ",
    type: ChannelType.GuildCategory,
    parentId: null,
    rawPosition: 0,
    overwrites: [],
  },
  {
    id: "ch-rules",
    name: "правила",
    type: ChannelType.GuildText,
    parentId: "cat-info",
    rawPosition: 0,
    topic: "Правила спільноти.",
    overwrites: [
      {
        id: EVERYONE_ID,
        type: 0,
        allow: { bitfield: 0n },
        deny: { bitfield: PermissionFlagsBits.SendMessages },
      },
      {
        id: "r-founder",
        type: 0,
        allow: { bitfield: PermissionFlagsBits.SendMessages },
        deny: { bitfield: 0n },
      },
      // member-overwrite (type 1) — ігнорується
      { id: "user-5", type: 1, allow: { bitfield: 0n }, deny: { bitfield: 0n } },
    ],
  },
  {
    id: "ch-forum",
    name: "bug-report",
    type: ChannelType.GuildForum,
    parentId: "cat-info",
    rawPosition: 1,
    availableTags: [{ name: "severity:critical" }, { name: "status:open" }],
    overwrites: [],
  },
  {
    id: "ch-voice",
    name: "Voice — Загальний",
    type: ChannelType.GuildVoice,
    parentId: null,
    rawPosition: 5,
    overwrites: [],
  },
  {
    id: "ch-stage",
    name: "сцена",
    type: ChannelType.GuildStageVoice,
    parentId: null,
    rawPosition: 6,
    overwrites: [],
  },
];

const state = mapGuildState({ everyoneId: EVERYONE_ID, roles: fakeRoles, channels: fakeChannels });

describe("mapGuildState", () => {
  it("ролі: bitfield → flag-імена, managed зберігається, @everyone присутній", () => {
    const founder = state.roles.find((r) => r.name === "🔴 Founder")!;
    expect(founder.permissions).toEqual(["Administrator"]);
    expect(state.roles.find((r) => r.name === "hart-iac")!.managed).toBe(true);
    expect(state.roles.some((r) => r.name === "@everyone")).toBe(true);
  });

  it("ролі відсортовані за position desc (стабільний snapshot)", () => {
    const positions = state.roles.map((r) => r.position);
    expect(positions).toEqual([...positions].sort((a, b) => b - a));
  });

  it("категорії виділені з каналів type=GuildCategory", () => {
    expect(state.categories).toHaveLength(1);
    expect(state.categories[0]!.name).toBe("📋 ІНФОРМАЦІЯ");
  });

  it("канал: parentId → ім'я категорії; без parent → null", () => {
    expect(state.channels.find((c) => c.name === "правила")!.category).toBe("📋 ІНФОРМАЦІЯ");
    expect(state.channels.find((c) => c.name === "Voice — Загальний")!.category).toBeNull();
  });

  it("overwrites: id → ім'я ролі, everyoneId → @everyone, member-overwrites відкинуті", () => {
    const rules = state.channels.find((c) => c.name === "правила")!;
    expect(rules.permissionOverwrites).toHaveLength(2);
    const everyone = rules.permissionOverwrites.find((ow) => ow.role === "@everyone")!;
    expect(everyone.deny).toEqual(["SendMessages"]);
    expect(rules.permissionOverwrites.some((ow) => ow.role === "🔴 Founder")).toBe(true);
  });

  it('forum-теги мапляться; невідомий тип каналу → "other"', () => {
    expect(state.channels.find((c) => c.name === "bug-report")!.tags).toEqual([
      "severity:critical",
      "status:open",
    ]);
    expect(state.channels.find((c) => c.name === "сцена")!.type).toBe("other");
  });
});
