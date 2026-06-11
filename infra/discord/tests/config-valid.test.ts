import { describe, expect, it } from "vitest";

import {
  CategoryConfigSchema,
  ChannelConfigSchema,
  RoleConfigSchema,
  ServerConfigSchema,
  validateConfigIntegrity,
} from "../config/types.js";

const validRole = {
  name: "⚪ Member",
  axis: "authority",
  color: 0x99aab5,
  hoist: false,
  permissions: ["SendMessages", "ReadMessageHistory"],
  position: 10,
};

const validChannel = {
  name: "правила",
  type: "GuildText",
  category: "📋 ІНФОРМАЦІЯ",
  topic: "Правила спільноти.",
};

describe("RoleConfigSchema", () => {
  it("accepts a valid role", () => {
    expect(RoleConfigSchema.parse(validRole)).toMatchObject({ name: "⚪ Member" });
  });

  it("rejects an unknown permission flag", () => {
    const bad = { ...validRole, permissions: ["NotARealPermission"] };
    expect(() => RoleConfigSchema.parse(bad)).toThrow(/permission/i);
  });

  it("rejects color outside 24-bit range", () => {
    expect(() => RoleConfigSchema.parse({ ...validRole, color: 0x1000000 })).toThrow();
    expect(() => RoleConfigSchema.parse({ ...validRole, color: -1 })).toThrow();
  });

  it("rejects unknown axis", () => {
    expect(() => RoleConfigSchema.parse({ ...validRole, axis: "vibes" })).toThrow();
  });
});

describe("ChannelConfigSchema", () => {
  it("accepts a valid text channel", () => {
    expect(ChannelConfigSchema.parse(validChannel)).toMatchObject({
      type: "GuildText",
      permissionOverwrites: [],
    });
  });

  it("accepts forum tags on GuildForum", () => {
    const forum = {
      ...validChannel,
      name: "bug-report",
      type: "GuildForum",
      tags: ["severity:critical", "status:open"],
    };
    expect(ChannelConfigSchema.parse(forum).tags).toHaveLength(2);
  });

  it("rejects forum tags on non-forum channel", () => {
    const bad = { ...validChannel, tags: ["готово"] };
    expect(() => ChannelConfigSchema.parse(bad)).toThrow(/GuildForum/);
  });

  it("accepts permission overwrites with allow/deny flag arrays", () => {
    const ch = {
      ...validChannel,
      permissionOverwrites: [
        { role: "@everyone", allow: [], deny: ["SendMessages"] },
        { role: "🟢 Verified-Manufacturer", allow: ["SendMessages"], deny: [] },
      ],
    };
    expect(ChannelConfigSchema.parse(ch).permissionOverwrites).toHaveLength(2);
  });
});

describe("CategoryConfigSchema / ServerConfigSchema", () => {
  it("accepts a valid category", () => {
    expect(
      CategoryConfigSchema.parse({ name: "📋 ІНФОРМАЦІЯ", position: 0 }).permissionOverwrites,
    ).toEqual([]);
  });

  it("accepts a valid server config", () => {
    const server = ServerConfigSchema.parse({
      name: "hart.crimea.ua",
      verificationLevel: "Low",
      defaultMessageNotifications: "OnlyMentions",
      systemChannel: "welcome",
    });
    expect(server.name).toBe("hart.crimea.ua");
  });
});

describe("validateConfigIntegrity", () => {
  const minimal = {
    roles: [RoleConfigSchema.parse(validRole)],
    categories: [CategoryConfigSchema.parse({ name: "📋 ІНФОРМАЦІЯ", position: 0 })],
    channels: [ChannelConfigSchema.parse(validChannel)],
  };

  it("passes on a consistent config", () => {
    expect(validateConfigIntegrity(minimal)).toEqual([]);
  });

  it("reports duplicate role names", () => {
    const errors = validateConfigIntegrity({
      ...minimal,
      roles: [...minimal.roles, ...minimal.roles],
    });
    expect(errors.some((e) => e.includes("⚪ Member"))).toBe(true);
  });

  it("reports a channel referencing a missing category", () => {
    const orphan = ChannelConfigSchema.parse({ ...validChannel, category: "🚫 НЕМАЄ" });
    const errors = validateConfigIntegrity({ ...minimal, channels: [orphan] });
    expect(errors.some((e) => e.includes("🚫 НЕМАЄ"))).toBe(true);
  });

  it("reports an overwrite referencing a missing role", () => {
    const ch = ChannelConfigSchema.parse({
      ...validChannel,
      permissionOverwrites: [{ role: "👻 Ghost", allow: [], deny: ["SendMessages"] }],
    });
    const errors = validateConfigIntegrity({ ...minimal, channels: [ch] });
    expect(errors.some((e) => e.includes("👻 Ghost"))).toBe(true);
  });

  it("does NOT report @everyone as a missing role", () => {
    const ch = ChannelConfigSchema.parse({
      ...validChannel,
      permissionOverwrites: [{ role: "@everyone", allow: [], deny: ["SendMessages"] }],
    });
    expect(validateConfigIntegrity({ ...minimal, channels: [ch] })).toEqual([]);
  });

  it("reports duplicate channel names within the same category", () => {
    const errors = validateConfigIntegrity({
      ...minimal,
      channels: [minimal.channels[0]!, minimal.channels[0]!],
    });
    expect(errors.some((e) => e.includes("правила"))).toBe(true);
  });
});
