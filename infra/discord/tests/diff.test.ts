import fc from "fast-check";
import { describe, expect, it } from "vitest";

import { CATEGORIES } from "../config/categories.js";
import { CHANNELS } from "../config/channels.js";
import { ROLES } from "../config/roles.js";
import type { CategoryConfig, ChannelConfig, RoleConfig } from "../config/types.js";
import {
  diffAll,
  diffCategories,
  diffChannels,
  diffRoles,
  type ActualCategory,
  type ActualChannel,
  type ActualRole,
} from "../lib/diff.js";

// ── Проєкція desired → actual: «ідеально застосований» config ─────────────
// Емулює стан Discord ПІСЛЯ успішного apply: actual position ролей спадає
// зверху вниз у порядку (desired position desc, stable).

let idCounter = 0;
const nextId = () => `id-${++idCounter}`;

function projectRoles(desired: RoleConfig[]): ActualRole[] {
  const byPosition = [...desired].sort((a, b) => b.position - a.position);
  return byPosition.map((r, i) => ({
    id: nextId(),
    name: r.name,
    color: r.color,
    hoist: r.hoist,
    permissions: [...r.permissions].sort(),
    position: byPosition.length - i, // Discord: більше = вище
    managed: false,
  }));
}

function projectCategories(desired: CategoryConfig[]): ActualCategory[] {
  return [...desired]
    .sort((a, b) => a.position - b.position)
    .map((c, i) => ({
      id: nextId(),
      name: c.name,
      position: i,
      permissionOverwrites: c.permissionOverwrites.map((ow) => ({
        role: ow.role,
        allow: [...ow.allow].sort(),
        deny: [...ow.deny].sort(),
      })),
    }));
}

function projectChannels(desired: ChannelConfig[]): ActualChannel[] {
  return desired.map((ch) => ({
    id: nextId(),
    name: ch.name,
    type: ch.type,
    category: ch.category,
    topic: ch.topic ?? null,
    ...(ch.tags === undefined ? {} : { tags: [...ch.tags] }),
    permissionOverwrites: ch.permissionOverwrites.map((ow) => ({
      role: ow.role,
      allow: [...ow.allow].sort(),
      deny: [...ow.deny].sort(),
    })),
  }));
}

const memberRole = ROLES.find((r) => r.name === "⚪ Member")!;

describe("diffRoles", () => {
  it("порожній actual → create для кожної desired-ролі у порядку config'у", () => {
    const ops = diffRoles([], ROLES);
    expect(ops).toHaveLength(ROLES.length);
    expect(ops.every((op) => op.type === "create")).toBe(true);
    expect(ops.map((op) => op.target)).toEqual(ROLES.map((r) => r.name));
  });

  it("ідеально застосований config → жодного op (idempotence)", () => {
    expect(diffRoles(projectRoles(ROLES), ROLES)).toEqual([]);
  });

  it("зміна кольору → update лише з полем color", () => {
    const actual = projectRoles(ROLES).map((r) =>
      r.name === "⚪ Member" ? { ...r, color: 0x000001 } : r,
    );
    const ops = diffRoles(actual, ROLES);
    expect(ops).toHaveLength(1);
    expect(ops[0]).toMatchObject({
      type: "update",
      target: "⚪ Member",
      fields: { color: { from: 0x000001, to: memberRole.color } },
    });
  });

  it("permissions порівнюються як множина (порядок не drift)", () => {
    const actual = projectRoles(ROLES).map((r) =>
      r.name === "⚪ Member" ? { ...r, permissions: [...r.permissions].reverse() } : r,
    );
    expect(diffRoles(actual, ROLES)).toEqual([]);
  });

  it("відсутній permission → update з полем permissions", () => {
    const actual = projectRoles(ROLES).map((r) =>
      r.name === "⚪ Member" ? { ...r, permissions: ["SendMessages" as const] } : r,
    );
    const ops = diffRoles(actual, ROLES);
    expect(ops).toHaveLength(1);
    expect(ops[0]!.type).toBe("update");
  });

  it("зайва роль у Discord → orphan (НЕ delete)", () => {
    const extra: ActualRole = {
      id: "extra",
      name: "🎁 Nitro Booster Legacy",
      color: 0,
      hoist: false,
      permissions: [],
      position: 1,
      managed: false,
    };
    const ops = diffRoles([...projectRoles(ROLES), extra], ROLES);
    expect(ops).toEqual([{ type: "orphan", entity: "role", target: "🎁 Nitro Booster Legacy" }]);
  });

  it("managed-ролі (бот-інтеграції) і @everyone — не orphan", () => {
    const bot: ActualRole = {
      id: "bot",
      name: "hart-iac",
      color: 0,
      hoist: false,
      permissions: ["Administrator"],
      position: 99,
      managed: true,
    };
    const everyone: ActualRole = {
      id: "ev",
      name: "@everyone",
      color: 0,
      hoist: false,
      permissions: [],
      position: 0,
      managed: false,
    };
    expect(diffRoles([...projectRoles(ROLES), bot, everyone], ROLES)).toEqual([]);
  });

  it("порушений відносний порядок authority-ролей → reorder", () => {
    const actual = projectRoles(ROLES).map((r) => {
      if (r.name === "🔴 Founder") return { ...r, position: 1 };
      return r;
    });
    const ops = diffRoles(actual, ROLES);
    expect(ops).toHaveLength(1);
    expect(ops[0]!.type).toBe("reorder");
  });

  it("перестановка всередині tie-групи (position 5 = 5) — НЕ drift", () => {
    // У desired усі selfid-ролі мають position 5 — їх взаємний порядок
    // у Discord не специфікований, не має генерувати вічний reorder.
    const projected = projectRoles(ROLES);
    const selfidNames = ROLES.filter((r) => r.axis === "selfid").map((r) => r.name);
    const selfidActual = projected.filter((r) => selfidNames.includes(r.name));
    const positions = selfidActual.map((r) => r.position);
    const rotated = new Map(
      selfidActual.map((r, i) => [r.name, positions[(i + 1) % positions.length]!]),
    );
    const actual = projected.map((r) =>
      rotated.has(r.name) ? { ...r, position: rotated.get(r.name)! } : r,
    );
    expect(diffRoles(actual, ROLES)).toEqual([]);
  });

  it("сортування ops стабільне: creates → updates → reorder → orphans", () => {
    const actual = [
      ...projectRoles(ROLES.filter((r) => r.name !== "⚪ Member")).map((r) =>
        r.name === "🔴 Founder" ? { ...r, color: 0x123456 } : r,
      ),
      {
        id: "x",
        name: "Zzz",
        color: 0,
        hoist: false,
        permissions: [],
        position: 1,
        managed: false,
      },
    ];
    const kinds = diffRoles(actual, ROLES).map((op) => op.type);
    expect(kinds).toEqual([...kinds].sort((a, b) => order(a) - order(b)));
    function order(k: string): number {
      return { create: 0, update: 1, reorder: 2, orphan: 3 }[k]!;
    }
  });

  it("PROPERTY: довільний config, ідеально застосований → diff порожній (100+ iter)", () => {
    const flagArb = fc.constantFrom(
      "SendMessages",
      "AttachFiles",
      "EmbedLinks",
      "AddReactions",
      "ManageMessages",
    );
    const roleArb = fc.record({
      name: fc
        .string({ minLength: 1, maxLength: 30 })
        .filter((s) => s.trim().length > 0 && s !== "@everyone"),
      axis: fc.constantFrom("authority" as const, "selfid" as const, "interest" as const),
      color: fc.integer({ min: 0, max: 0xffffff }),
      hoist: fc.boolean(),
      permissions: fc.uniqueArray(flagArb, { maxLength: 5 }),
      position: fc.integer({ min: 0, max: 100 }),
    });
    fc.assert(
      fc.property(
        fc.uniqueArray(roleArb, { selector: (r) => r.name, minLength: 1, maxLength: 15 }),
        (roles) => {
          const desired = roles as RoleConfig[];
          expect(diffRoles(projectRoles(desired), desired)).toEqual([]);
        },
      ),
      { numRuns: 150 },
    );
  });

  it("PROPERTY: «створити те, чого нема» — кількість creates = |desired \\ actual|", () => {
    fc.assert(
      fc.property(fc.integer({ min: 0, max: ROLES.length }), (keep) => {
        const actual = projectRoles(ROLES.slice(0, keep));
        const creates = diffRoles(actual, ROLES).filter((op) => op.type === "create");
        expect(creates).toHaveLength(ROLES.length - keep);
      }),
      { numRuns: 50 },
    );
  });
});

describe("diffCategories", () => {
  it("idempotence на канонічному config'і", () => {
    expect(diffCategories(projectCategories(CATEGORIES), CATEGORIES)).toEqual([]);
  });

  it("відсутня категорія → create; зайва → orphan", () => {
    const actual = projectCategories(CATEGORIES.slice(1));
    const extra: ActualCategory = {
      id: "x",
      name: "🗑️ СТАРЕ",
      position: 99,
      permissionOverwrites: [],
    };
    const ops = diffCategories([...actual, extra], CATEGORIES);
    expect(ops.filter((op) => op.type === "create").map((op) => op.target)).toEqual([
      "📋 ІНФОРМАЦІЯ",
    ]);
    expect(ops.filter((op) => op.type === "orphan").map((op) => op.target)).toEqual(["🗑️ СТАРЕ"]);
  });

  it("drift у gated-overwrite → update", () => {
    const actual = projectCategories(CATEGORIES).map((c) =>
      c.name === "🐛 ТЕХ-ПІДТРИМКА" ? { ...c, permissionOverwrites: [] } : c,
    );
    const ops = diffCategories(actual, CATEGORIES);
    expect(ops).toHaveLength(1);
    expect(ops[0]).toMatchObject({ type: "update", target: "🐛 ТЕХ-ПІДТРИМКА" });
  });
});

describe("diffChannels", () => {
  it("idempotence на канонічному config'і", () => {
    expect(diffChannels(projectChannels(CHANNELS), CHANNELS)).toEqual([]);
  });

  it("зміна topic → update з полем topic", () => {
    const actual = projectChannels(CHANNELS).map((ch) =>
      ch.name === "правила" ? { ...ch, topic: "застарілий topic" } : ch,
    );
    const ops = diffChannels(actual, CHANNELS);
    expect(ops).toHaveLength(1);
    expect(ops[0]).toMatchObject({ type: "update", target: "📋 ІНФОРМАЦІЯ/правила" });
  });

  it("forum-теги порівнюються як множина", () => {
    const actual = projectChannels(CHANNELS).map((ch) =>
      ch.name === "bug-report" ? { ...ch, tags: [...ch.tags!].reverse() } : ch,
    );
    expect(diffChannels(actual, CHANNELS)).toEqual([]);
  });

  it("відсутній forum-тег → update", () => {
    const actual = projectChannels(CHANNELS).map((ch) =>
      ch.name === "bug-report" ? { ...ch, tags: ch.tags!.slice(1) } : ch,
    );
    const ops = diffChannels(actual, CHANNELS);
    expect(ops).toHaveLength(1);
    expect(ops[0]!.type).toBe("update");
  });

  it("НЕзадекларований overwrite в actual — не drift (declared-subset semantics)", () => {
    // Discord синхронізує category-overwrites у канали — у actual каналів
    // gated-категорій є успадковані overwrites, яких нема у config каналу.
    const actual = projectChannels(CHANNELS).map((ch) =>
      ch.name === "вибір-виробника"
        ? {
            ...ch,
            permissionOverwrites: [
              { role: "@everyone", allow: [], deny: ["ViewChannel" as const] },
            ],
          }
        : ch,
    );
    expect(diffChannels(actual, CHANNELS)).toEqual([]);
  });

  it("задеклароване, але відсутнє в actual overwrite → update", () => {
    const actual = projectChannels(CHANNELS).map((ch) =>
      ch.name === "виробники-офіційно" ? { ...ch, permissionOverwrites: [] } : ch,
    );
    const ops = diffChannels(actual, CHANNELS);
    expect(ops).toHaveLength(1);
    expect(ops[0]).toMatchObject({ type: "update", target: "🏭 ВИРОБНИЦТВО/виробники-офіційно" });
  });

  it("канал поза config'ом → orphan; перейменована категорія → create+orphan", () => {
    const stray: ActualChannel = {
      id: "s",
      name: "random-стихійний",
      type: "GuildText",
      category: null,
      topic: null,
      permissionOverwrites: [],
    };
    const ops = diffChannels([...projectChannels(CHANNELS), stray], CHANNELS);
    expect(ops).toEqual([
      { type: "orphan", entity: "channel", target: "(без категорії)/random-стихійний" },
    ]);
  });
});

describe("diffAll", () => {
  it("збирає ролі+категорії+канали; на ідеальному стані — порожній", () => {
    const ops = diffAll(
      {
        roles: projectRoles(ROLES),
        categories: projectCategories(CATEGORIES),
        channels: projectChannels(CHANNELS),
      },
      { roles: ROLES, categories: CATEGORIES, channels: CHANNELS },
    );
    expect(ops).toEqual([]);
  });

  it("на порожньому сервері — рівно 12+8+21 creates у порядку roles→categories→channels", () => {
    const ops = diffAll(
      { roles: [], categories: [], channels: [] },
      { roles: ROLES, categories: CATEGORIES, channels: CHANNELS },
    );
    expect(ops).toHaveLength(12 + 8 + 21);
    expect(ops.every((op) => op.type === "create")).toBe(true);
    const entities = ops.map((op) => op.entity);
    expect(entities.indexOf("category")).toBe(12);
    expect(entities.indexOf("channel")).toBe(20);
  });
});
