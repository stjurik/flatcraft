import { describe, expect, it } from "vitest";

import type { ActualState } from "../lib/diff.js";
import { renderSnapshotMarkdown } from "../lib/markdown.js";

const emptyState: ActualState = { roles: [], categories: [], channels: [] };

const oneRole: ActualState = {
  roles: [
    {
      id: "1",
      name: "🔴 Founder",
      color: 0xed4245,
      hoist: true,
      permissions: ["Administrator"],
      position: 100,
      managed: false,
    },
  ],
  categories: [],
  channels: [],
};

const full: ActualState = {
  roles: [
    ...oneRole.roles,
    {
      id: "2",
      name: "⚪ Member",
      color: 0x99aab5,
      hoist: false,
      permissions: ["AddReactions", "SendMessages"],
      position: 10,
      managed: false,
    },
  ],
  categories: [
    {
      id: "10",
      name: "🐛 ТЕХ-ПІДТРИМКА",
      position: 0,
      permissionOverwrites: [
        { role: "@everyone", allow: [], deny: ["ViewChannel"] },
        { role: "🐛 interest/Support", allow: ["ViewChannel"], deny: [] },
      ],
    },
  ],
  channels: [
    {
      id: "20",
      name: "bug-report",
      type: "GuildForum",
      category: "🐛 ТЕХ-ПІДТРИМКА",
      topic: null,
      tags: ["severity:critical", "status:open"],
      permissionOverwrites: [],
    },
    {
      id: "21",
      name: "помилки-валідації",
      type: "GuildText",
      category: "🐛 ТЕХ-ПІДТРИМКА",
      topic: "Розбір 422.",
      permissionOverwrites: [{ role: "@everyone", allow: [], deny: ["SendMessages"] }],
    },
  ],
};

describe("renderSnapshotMarkdown", () => {
  it("порожній стан — валідний markdown з заголовком і порожніми секціями", () => {
    const md = renderSnapshotMarkdown(emptyState, { guildName: "hart.crimea.ua" });
    expect(md).toContain("# Discord — hart.crimea.ua");
    expect(md).toContain("## Ролі");
    expect(md).toContain("## Категорії та канали");
  });

  it("НЕ містить timestamp — однаковий стан → байт-у-байт однаковий doc (drift-detection)", () => {
    const a = renderSnapshotMarkdown(full, { guildName: "g" });
    const b = renderSnapshotMarkdown(full, { guildName: "g" });
    expect(a).toBe(b);
    expect(a).not.toMatch(/\d{4}-\d{2}-\d{2}T\d{2}/);
  });

  it("роль рендериться з hex-кольором, hoist і permissions", () => {
    const md = renderSnapshotMarkdown(oneRole, { guildName: "g" });
    expect(md).toContain("🔴 Founder");
    expect(md).toContain("#ed4245");
    expect(md).toContain("Administrator");
  });

  it("канали згруповані під категорією; форум показує теги", () => {
    const md = renderSnapshotMarkdown(full, { guildName: "g" });
    expect(md).toContain("### 🐛 ТЕХ-ПІДТРИМКА");
    expect(md).toContain("bug-report");
    expect(md).toContain("severity:critical");
  });

  it("permission-матриця: цільовий канал/категорія × роль × allow/deny", () => {
    const md = renderSnapshotMarkdown(full, { guildName: "g" });
    expect(md).toContain("## Permission-overwrites");
    expect(md).toContain("🐛 interest/Support");
    expect(md).toContain("ViewChannel");
    expect(md).toContain("SendMessages");
  });

  it("екранує | у назвах (markdown-таблиці не ламаються)", () => {
    const tricky: ActualState = {
      ...emptyState,
      roles: [{ ...oneRole.roles[0]!, name: "a|b" }],
    };
    const md = renderSnapshotMarkdown(tricky, { guildName: "g" });
    expect(md).toContain("a\\|b");
  });
});
