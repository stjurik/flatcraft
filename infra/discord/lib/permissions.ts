import { PermissionFlagsBits } from "discord.js";

import type { PermissionFlag } from "../config/types.js";

// Конвертація на API-boundary: config/snapshot тримають ІМЕНА флагів
// (JSON-серіалізовні, читабельні у PR-diff), Discord API хоче bigint-bitfield.

export function flagsToBitfield(flags: readonly PermissionFlag[]): bigint {
  let bitfield = 0n;
  for (const flag of flags) {
    bitfield |= PermissionFlagsBits[flag];
  }
  return bitfield;
}

/**
 * Зворотна конвертація. Невідомі біти (нові permission'и Discord, яких ще
 * нема у нашій версії discord.js) мовчки ігноруються — forward-compat.
 * Результат відсортований: детермінований snapshot → стабільний git-diff.
 */
export function bitfieldToFlags(bitfield: bigint): PermissionFlag[] {
  const flags: PermissionFlag[] = [];
  for (const [name, bit] of Object.entries(PermissionFlagsBits)) {
    if ((bitfield & bit) === bit) flags.push(name as PermissionFlag);
  }
  return flags.sort();
}
