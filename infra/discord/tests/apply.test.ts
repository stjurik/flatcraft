import { describe, expect, it } from "vitest";

import { CATEGORIES } from "../config/categories.js";
import { CHANNELS } from "../config/channels.js";
import { ROLES } from "../config/roles.js";
import type { FullConfig } from "../config/types.js";
import {
  applyOps,
  missingGuildFeatures,
  requiredGuildFeatures,
  type ApplyPorts,
} from "../lib/apply.js";
import { diffAll, type DiffOp } from "../lib/diff.js";
import { formatOps } from "../lib/format-ops.js";

const CONFIG: FullConfig = { roles: ROLES, categories: CATEGORIES, channels: CHANNELS };

function recordingPorts(failOn: string[] = []): { calls: string[]; ports: ApplyPorts } {
  const calls: string[] = [];
  const record =
    (label: string) =>
    (target: { name: string } | string): Promise<void> => {
      const name = typeof target === "string" ? target : target.name;
      calls.push(`${label}:${name}`);
      if (failOn.includes(name)) return Promise.reject(new Error(`fail ${name}`));
      return Promise.resolve();
    };
  return {
    calls,
    ports: {
      createRole: record("createRole"),
      updateRole: record("updateRole"),
      reorderRoles: (order) => record("reorderRoles")(order.join(">")),
      createCategory: record("createCategory"),
      updateCategory: record("updateCategory"),
      reorderCategories: (order) => record("reorderCategories")(order.join(">")),
      createChannel: record("createChannel"),
      updateChannel: record("updateChannel"),
    },
  };
}

const noSleep = () => Promise.resolve();

describe("applyOps", () => {
  it("порожній diff → нічого не викликає, applied=0", async () => {
    const { calls, ports } = recordingPorts();
    const outcome = await applyOps([], CONFIG, ports, { sleep: noSleep });
    expect(calls).toEqual([]);
    expect(outcome).toMatchObject({ applied: 0, failed: [], orphans: [] });
  });

  it("порожній сервер: створює у порядку roles → categories → channels", async () => {
    const ops = diffAll({ roles: [], categories: [], channels: [] }, CONFIG);
    const { calls, ports } = recordingPorts();
    const outcome = await applyOps(ops, CONFIG, ports, { sleep: noSleep });
    expect(outcome.applied).toBe(12 + 8 + 21);
    expect(outcome.failed).toEqual([]);
    const kinds = calls.map((c) => c.split(":")[0]);
    expect(kinds.lastIndexOf("createRole")).toBeLessThan(kinds.indexOf("createCategory"));
    expect(kinds.lastIndexOf("createCategory")).toBeLessThan(kinds.indexOf("createChannel"));
  });

  it("orphan: жодного виклику портів, лише warning-колекція (НЕ delete)", async () => {
    const ops: DiffOp[] = [{ type: "orphan", entity: "role", target: "🎁 Стара роль" }];
    const { calls, ports } = recordingPorts();
    const outcome = await applyOps(ops, CONFIG, ports, { sleep: noSleep });
    expect(calls).toEqual([]);
    expect(outcome.orphans).toEqual([{ entity: "role", target: "🎁 Стара роль" }]);
    expect(outcome.failed).toEqual([]);
  });

  it("помилка операції: записується у failed, решта ops виконуються далі", async () => {
    const ops = diffAll({ roles: [], categories: [], channels: [] }, CONFIG);
    const { ports } = recordingPorts(["⚪ Member"]);
    const outcome = await applyOps(ops, CONFIG, ports, { sleep: noSleep });
    expect(outcome.failed).toHaveLength(1);
    expect(outcome.failed[0]!.target).toBe("⚪ Member");
    expect(outcome.applied).toBe(12 + 8 + 21 - 1);
  });

  it("sleep викликається між write-операціями (rate-limit safety)", async () => {
    let sleeps = 0;
    const ops = diffAll({ roles: [], categories: [], channels: [] }, CONFIG).slice(0, 5);
    const { ports } = recordingPorts();
    await applyOps(ops, CONFIG, ports, {
      sleep: () => {
        sleeps++;
        return Promise.resolve();
      },
    });
    expect(sleeps).toBe(5);
  });

  it("update маршрутизується у відповідний порт", async () => {
    const ops: DiffOp[] = [
      {
        type: "update",
        entity: "channel",
        target: "📋 ІНФОРМАЦІЯ/правила",
        fields: { topic: { from: "old", to: "new" } },
      },
    ];
    const { calls, ports } = recordingPorts();
    const outcome = await applyOps(ops, CONFIG, ports, { sleep: noSleep });
    expect(calls).toEqual(["updateChannel:📋 ІНФОРМАЦІЯ/правила"]);
    expect(outcome.applied).toBe(1);
  });

  it("create для цілі поза config'ом → failed (не crash)", async () => {
    const ops: DiffOp[] = [{ type: "create", entity: "role", target: "👻 Невідома" }];
    const { calls, ports } = recordingPorts();
    const outcome = await applyOps(ops, CONFIG, ports, { sleep: noSleep });
    expect(calls).toEqual([]);
    expect(outcome.failed).toHaveLength(1);
  });

  it("reorder викликає reorderRoles з порядком top→bottom", async () => {
    const ops: DiffOp[] = [
      { type: "reorder", entity: "role", target: "(порядок ролей)", order: ["A", "B"] },
    ];
    const { calls, ports } = recordingPorts();
    await applyOps(ops, CONFIG, ports, { sleep: noSleep });
    expect(calls).toEqual(["reorderRoles:A>B"]);
  });
});

describe("requiredGuildFeatures", () => {
  it("канонічний config вимагає COMMUNITY (є Announcement + Forum)", () => {
    expect(requiredGuildFeatures(CHANNELS)).toEqual(["COMMUNITY"]);
  });

  it("лише text/voice → нічого не вимагає", () => {
    const plain = CHANNELS.filter((ch) => ch.type === "GuildText" || ch.type === "GuildVoice");
    expect(requiredGuildFeatures(plain)).toEqual([]);
  });
});

describe("missingGuildFeatures", () => {
  it("Community увімкнено → нічого не бракує", () => {
    expect(missingGuildFeatures(CHANNELS, ["COMMUNITY", "NEWS"])).toEqual([]);
  });

  it("Community вимкнено → бракує COMMUNITY", () => {
    expect(missingGuildFeatures(CHANNELS, ["NEWS"])).toEqual(["COMMUNITY"]);
  });

  it("undefined features (частковий guild до REST-fetch) → не падає, рапортує брак", () => {
    // Регресія: apply падав з 'Cannot read properties of undefined (reading
    // \"includes\")' саме на цьому — частковий guild мав features=undefined.
    expect(() => missingGuildFeatures(CHANNELS, undefined)).not.toThrow();
    expect(missingGuildFeatures(CHANNELS, undefined)).toEqual(["COMMUNITY"]);
  });

  it("config без Community-каналів → байдуже до features", () => {
    const plain = CHANNELS.filter((ch) => ch.type === "GuildText" || ch.type === "GuildVoice");
    expect(missingGuildFeatures(plain, undefined)).toEqual([]);
  });
});

describe("formatOps", () => {
  it("порожній список → повідомлення про відсутність drift", () => {
    expect(formatOps([])).toContain("немає drift");
  });

  it("create/update/orphan мають розпізнавані маркери і ціль", () => {
    const ops: DiffOp[] = [
      { type: "create", entity: "role", target: "⚪ Member" },
      {
        type: "update",
        entity: "channel",
        target: "📋 ІНФОРМАЦІЯ/правила",
        fields: { topic: { from: "a", to: "b" } },
      },
      { type: "orphan", entity: "category", target: "🗑️ СТАРЕ" },
    ];
    const text = formatOps(ops);
    expect(text).toContain("+ create role ⚪ Member");
    expect(text).toContain("~ update channel 📋 ІНФОРМАЦІЯ/правила");
    expect(text).toContain("topic");
    expect(text).toContain("! orphan category 🗑️ СТАРЕ");
    expect(text).toMatch(/вручну|config/);
  });
});
