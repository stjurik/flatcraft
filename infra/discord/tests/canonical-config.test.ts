import { describe, expect, it } from "vitest";

import { CATEGORIES } from "../config/categories.js";
import { CHANNELS } from "../config/channels.js";
import { ROLES } from "../config/roles.js";
import { SERVER } from "../config/server.js";
import { validateConfigIntegrity } from "../config/types.js";

describe("canonical ROLES", () => {
  it("містить рівно 12 ролей: 4 authority + 4 selfid + 4 interest", () => {
    expect(ROLES).toHaveLength(12);
    const byAxis = (axis: string) => ROLES.filter((r) => r.axis === axis);
    expect(byAxis("authority")).toHaveLength(4);
    expect(byAxis("selfid")).toHaveLength(4);
    expect(byAxis("interest")).toHaveLength(4);
  });

  it("Founder — Administrator, position 100, hoist", () => {
    const founder = ROLES.find((r) => r.name === "🔴 Founder");
    expect(founder).toMatchObject({
      axis: "authority",
      color: 0xed4245,
      hoist: true,
      permissions: ["Administrator"],
      position: 100,
    });
  });

  it("selfid та interest ролі — без permissions (доступ дають overwrites)", () => {
    for (const role of ROLES.filter((r) => r.axis !== "authority")) {
      expect(role.permissions, role.name).toEqual([]);
      expect(role.hoist, role.name).toBe(false);
    }
  });

  it("authority-ієрархія впорядкована: Founder > Moderator > Verified-Manufacturer > Member", () => {
    const pos = (name: string) => ROLES.find((r) => r.name.includes(name))!.position;
    expect(pos("Founder")).toBeGreaterThan(pos("Moderator"));
    expect(pos("Moderator")).toBeGreaterThan(pos("Verified-Manufacturer"));
    expect(pos("Verified-Manufacturer")).toBeGreaterThan(pos("Member"));
  });
});

describe("canonical CATEGORIES + CHANNELS", () => {
  it("7 категорій з унікальними позиціями 0..6", () => {
    expect(CATEGORIES).toHaveLength(8);
    const positions = CATEGORIES.map((c) => c.position).sort((a, b) => a - b);
    expect(positions).toEqual([0, 1, 2, 3, 4, 5, 6, 7]);
  });

  it("21 канал з правильним розподілом по категоріях", () => {
    expect(CHANNELS).toHaveLength(21);
    const inCat = (cat: string) => CHANNELS.filter((ch) => ch.category.includes(cat)).length;
    expect(inCat("ІНФОРМАЦІЯ")).toBe(4);
    expect(inCat("ЗАГАЛЬНЕ")).toBe(2);
    expect(inCat("ПРОЄКТУВАННЯ")).toBe(3);
    expect(inCat("ТЕХ-ПІДТРИМКА")).toBe(3);
    expect(inCat("ВИРОБНИЦТВО")).toBe(3);
    expect(inCat("НАВЧАННЯ")).toBe(2);
    expect(inCat("ГОЛОСОВІ")).toBe(2);
    expect(inCat("МОДЕРАЦІЯ")).toBe(2);
  });

  it("🔒 МОДЕРАЦІЯ — mod-only: @everyone deny ViewChannel, Moderator allow", () => {
    const cat = CATEGORIES.find((c) => c.name.includes("МОДЕРАЦІЯ"))!;
    const everyone = cat.permissionOverwrites.find((ow) => ow.role === "@everyone");
    const mod = cat.permissionOverwrites.find((ow) => ow.role === "🟠 Moderator");
    expect(everyone?.deny).toContain("ViewChannel");
    expect(mod?.allow).toContain("ViewChannel");
    // жодної interest-ролі — це не opt-in категорія
    expect(cat.permissionOverwrites.some((ow) => ow.role.startsWith("🐛 interest"))).toBe(false);
  });

  it("3 forum-канали; всі теги ≤ 20 символів (Discord API limit)", () => {
    const forums = CHANNELS.filter((ch) => ch.type === "GuildForum");
    expect(forums.map((f) => f.name).sort()).toEqual([
      "bug-report",
      "показуй-проєкти",
      "поради-з-проєктування",
    ]);
    for (const forum of forums) {
      expect(forum.tags!.length).toBeGreaterThan(0);
      for (const tag of forum.tags!) {
        expect(tag.length, `тег "${tag}" у #${forum.name}`).toBeLessThanOrEqual(20);
      }
    }
  });

  it("bug-report має severity/status/tpl теги", () => {
    const bugReport = CHANNELS.find((ch) => ch.name === "bug-report")!;
    const tags = bugReport.tags!;
    expect(tags.filter((t) => t.startsWith("severity:"))).toHaveLength(4);
    expect(tags.filter((t) => t.startsWith("status:"))).toHaveLength(3);
    expect(tags.filter((t) => t.startsWith("tpl:"))).toHaveLength(5);
  });

  it("gated-категорії: deny ViewChannel для @everyone + allow для своєї interest-ролі", () => {
    const gates: [string, string][] = [
      ["ТЕХ-ПІДТРИМКА", "🐛 interest/Support"],
      ["ВИРОБНИЦТВО", "🏭 interest/Production"],
      ["НАВЧАННЯ", "📚 interest/Learning"],
    ];
    for (const [catName, roleName] of gates) {
      const cat = CATEGORIES.find((c) => c.name.includes(catName))!;
      const everyone = cat.permissionOverwrites.find((ow) => ow.role === "@everyone");
      const interest = cat.permissionOverwrites.find((ow) => ow.role === roleName);
      expect(everyone?.deny, catName).toContain("ViewChannel");
      expect(interest?.allow, catName).toContain("ViewChannel");
    }
  });

  it("read-only канали: deny SendMessages для @everyone", () => {
    for (const name of ["правила", "оголошення", "ресурси", "туторіали"]) {
      const ch = CHANNELS.find((c) => c.name === name)!;
      const everyone = ch.permissionOverwrites.find((ow) => ow.role === "@everyone");
      expect(everyone?.deny, name).toContain("SendMessages");
    }
  });

  it("виробники-офіційно: write лише для Verified-Manufacturer", () => {
    const ch = CHANNELS.find((c) => c.name === "виробники-офіційно")!;
    const everyone = ch.permissionOverwrites.find((ow) => ow.role === "@everyone");
    const vm = ch.permissionOverwrites.find((ow) => ow.role === "🟢 Verified-Manufacturer");
    expect(everyone?.deny).toContain("SendMessages");
    expect(vm?.allow).toContain("SendMessages");
  });
});

describe("крос-файлова цілісність", () => {
  it("validateConfigIntegrity на канонічному config'і — без помилок", () => {
    expect(
      validateConfigIntegrity({ roles: ROLES, categories: CATEGORIES, channels: CHANNELS }),
    ).toEqual([]);
  });

  it("SERVER — hart.crimea.ua з system-каналом welcome", () => {
    expect(SERVER).toMatchObject({ name: "hart.crimea.ua", systemChannel: "welcome" });
  });
});
