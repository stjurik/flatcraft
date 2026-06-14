import { PermissionFlagsBits } from "discord.js";
import { describe, expect, it } from "vitest";

import { bitfieldToFlags, flagsToBitfield } from "../lib/permissions.js";

describe("flagsToBitfield", () => {
  it("порожній масив → 0n", () => {
    expect(flagsToBitfield([])).toBe(0n);
  });

  it("один флаг → його біт", () => {
    expect(flagsToBitfield(["SendMessages"])).toBe(PermissionFlagsBits.SendMessages);
  });

  it("кілька флагів → OR бітів", () => {
    expect(flagsToBitfield(["SendMessages", "AttachFiles"])).toBe(
      PermissionFlagsBits.SendMessages | PermissionFlagsBits.AttachFiles,
    );
  });

  it("дублікати не змінюють результат (OR idempotent)", () => {
    expect(flagsToBitfield(["SendMessages", "SendMessages"])).toBe(
      PermissionFlagsBits.SendMessages,
    );
  });

  it("Administrator — великий біт (> 2^30), bigint не втрачає точність", () => {
    expect(flagsToBitfield(["Administrator"])).toBe(1n << 3n);
    // Біти за межами Number.MAX_SAFE_INTEGER (напр. SendVoiceMessages = 1<<46).
    expect(flagsToBitfield(["SendVoiceMessages"])).toBe(1n << 46n);
  });
});

describe("bitfieldToFlags", () => {
  it("0n → порожній масив", () => {
    expect(bitfieldToFlags(0n)).toEqual([]);
  });

  it("roundtrip: flags → bitfield → ті самі flags (відсортовані)", () => {
    const flags = ["SendMessages", "AttachFiles", "EmbedLinks", "AddReactions"] as const;
    const round = bitfieldToFlags(flagsToBitfield([...flags]));
    expect(round).toEqual([...flags].sort());
  });

  it("результат відсортований і стабільний незалежно від порядку входу", () => {
    const a = bitfieldToFlags(flagsToBitfield(["EmbedLinks", "SendMessages"]));
    const b = bitfieldToFlags(flagsToBitfield(["SendMessages", "EmbedLinks"]));
    expect(a).toEqual(b);
    expect(a).toEqual([...a].sort());
  });

  it("невідомі біти ігноруються (forward-compat з новими permission'ами Discord)", () => {
    const unknownBit = 1n << 62n;
    expect(bitfieldToFlags(PermissionFlagsBits.SendMessages | unknownBit)).toEqual([
      "SendMessages",
    ]);
  });

  it("усі відомі біти разом → повний список флагів", () => {
    const all = Object.values(PermissionFlagsBits).reduce((acc, bit) => acc | bit, 0n);
    expect(bitfieldToFlags(all).length).toBe(Object.keys(PermissionFlagsBits).length);
  });
});
