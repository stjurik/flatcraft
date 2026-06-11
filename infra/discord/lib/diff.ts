import type {
  CategoryConfig,
  ChannelConfig,
  ChannelKind,
  FullConfig,
  PermissionFlag,
  RoleConfig,
} from "../config/types.js";

// ── Actual state: plain-об'єкти (snapshot), НЕ discord.js класи ────────────
// Pure diff тестується без моків discord.js; мапінг API→plain — у scripts/.

export interface ActualOverwrite {
  // Ім'я ролі (resolved зі snapshot'у) або "@everyone".
  role: string;
  allow: PermissionFlag[];
  deny: PermissionFlag[];
}

export interface ActualRole {
  id: string;
  name: string;
  color: number;
  hoist: boolean;
  permissions: PermissionFlag[];
  position: number; // Discord: більше = вище
  managed: boolean; // інтеграційні ролі (бот) — не наша юрисдикція
}

export interface ActualCategory {
  id: string;
  name: string;
  position: number; // Discord: менше = вище
  permissionOverwrites: ActualOverwrite[];
}

export interface ActualChannel {
  id: string;
  name: string;
  type: ChannelKind | "other";
  category: string | null; // ім'я категорії; null — поза категоріями
  topic: string | null;
  tags?: string[]; // лише форуми
  permissionOverwrites: ActualOverwrite[];
}

export interface ActualState {
  roles: ActualRole[];
  categories: ActualCategory[];
  channels: ActualChannel[];
}

export type Entity = "role" | "category" | "channel";

export interface FieldChange {
  from: unknown;
  to: unknown;
}

export type DiffOp =
  | { type: "create"; entity: Entity; target: string }
  | { type: "update"; entity: Entity; target: string; fields: Record<string, FieldChange> }
  | { type: "reorder"; entity: "role" | "category"; target: string; order: string[] }
  | { type: "orphan"; entity: Entity; target: string };

const EVERYONE = "@everyone";

function setEq(a: readonly string[], b: readonly string[]): boolean {
  const sa = new Set(a);
  const sb = new Set(b);
  return sa.size === sb.size && [...sa].every((v) => sb.has(v));
}

/**
 * Declared-subset semantics: кожен ЗАДЕКЛАРОВАНИЙ overwrite мусить існувати
 * в actual з тими самими allow/deny. Зайві overwrites в actual — не drift
 * (Discord синхронізує category-overwrites у канали; повна картина — у snapshot).
 */
function overwritesSatisfied(
  declared: readonly { role: string; allow: PermissionFlag[]; deny: PermissionFlag[] }[],
  actual: readonly ActualOverwrite[],
): boolean {
  return declared.every((d) => {
    const found = actual.find((a) => a.role === d.role);
    return found !== undefined && setEq(found.allow, d.allow) && setEq(found.deny, d.deny);
  });
}

/**
 * Перевірка відносного порядку: для кожної пари з СТРОГО різними desired
 * positions фактичний порядок мусить збігатись. Tie-групи (однаковий desired
 * position) не порівнюються — їх взаємний порядок у Discord не специфікований,
 * інакше отримали б вічний reorder-drift.
 */
function orderViolated<T>(
  matched: readonly T[],
  desiredPos: (item: T) => number,
  actualPos: (item: T) => number,
): boolean {
  // Обидві осі монотонні в один бік: ролі — більше = вище у списку і там, і
  // там; категорії — менше = вище і у config'і, і у Discord. Тож достатньо
  // вимагати однакового знаку порівняння.
  for (let i = 0; i < matched.length; i++) {
    for (let j = i + 1; j < matched.length; j++) {
      const a = matched[i]!;
      const b = matched[j]!;
      if (desiredPos(a) === desiredPos(b)) continue;
      if (desiredPos(a) > desiredPos(b) !== actualPos(a) > actualPos(b)) return true;
    }
  }
  return false;
}

export function diffRoles(actual: ActualRole[], desired: RoleConfig[]): DiffOp[] {
  const relevant = actual.filter((r) => !r.managed && r.name !== EVERYONE);
  const actualByName = new Map(relevant.map((r) => [r.name, r]));
  const desiredNames = new Set(desired.map((r) => r.name));

  const creates: DiffOp[] = [];
  const updates: DiffOp[] = [];

  for (const want of desired) {
    const have = actualByName.get(want.name);
    if (have === undefined) {
      creates.push({ type: "create", entity: "role", target: want.name });
      continue;
    }
    const fields: Record<string, FieldChange> = {};
    if (have.color !== want.color) fields["color"] = { from: have.color, to: want.color };
    if (have.hoist !== want.hoist) fields["hoist"] = { from: have.hoist, to: want.hoist };
    if (!setEq(have.permissions, want.permissions)) {
      fields["permissions"] = {
        from: [...have.permissions].sort(),
        to: [...want.permissions].sort(),
      };
    }
    if (Object.keys(fields).length > 0) {
      updates.push({ type: "update", entity: "role", target: want.name, fields });
    }
  }

  // Reorder перевіряємо лише коли всі desired-ролі вже існують: після creates
  // позиції все одно виставляються наново, drift добереться наступним diff'ом.
  const reorders: DiffOp[] = [];
  if (creates.length === 0) {
    const matched = desired.filter((d) => actualByName.has(d.name));
    if (
      orderViolated(
        matched,
        (d) => d.position,
        (d) => actualByName.get(d.name)!.position,
      )
    ) {
      const order = [...matched].sort((a, b) => b.position - a.position).map((r) => r.name);
      reorders.push({ type: "reorder", entity: "role", target: "(порядок ролей)", order });
    }
  }

  const orphans: DiffOp[] = relevant
    .filter((r) => !desiredNames.has(r.name))
    .map((r): DiffOp => ({ type: "orphan", entity: "role", target: r.name }))
    .sort((a, b) => a.target.localeCompare(b.target));

  return [...creates, ...updates, ...reorders, ...orphans];
}

export function diffCategories(actual: ActualCategory[], desired: CategoryConfig[]): DiffOp[] {
  const actualByName = new Map(actual.map((c) => [c.name, c]));
  const desiredNames = new Set(desired.map((c) => c.name));

  const creates: DiffOp[] = [];
  const updates: DiffOp[] = [];

  for (const want of desired) {
    const have = actualByName.get(want.name);
    if (have === undefined) {
      creates.push({ type: "create", entity: "category", target: want.name });
      continue;
    }
    if (!overwritesSatisfied(want.permissionOverwrites, have.permissionOverwrites)) {
      updates.push({
        type: "update",
        entity: "category",
        target: want.name,
        fields: {
          permissionOverwrites: { from: have.permissionOverwrites, to: want.permissionOverwrites },
        },
      });
    }
  }

  const reorders: DiffOp[] = [];
  if (creates.length === 0) {
    const matched = desired.filter((d) => actualByName.has(d.name));
    if (
      orderViolated(
        matched,
        (d) => d.position,
        (d) => actualByName.get(d.name)!.position,
      )
    ) {
      const order = [...matched].sort((a, b) => a.position - b.position).map((c) => c.name);
      reorders.push({ type: "reorder", entity: "category", target: "(порядок категорій)", order });
    }
  }

  const orphans: DiffOp[] = actual
    .filter((c) => !desiredNames.has(c.name))
    .map((c): DiffOp => ({ type: "orphan", entity: "category", target: c.name }))
    .sort((a, b) => a.target.localeCompare(b.target));

  return [...creates, ...updates, ...reorders, ...orphans];
}

const channelKey = (category: string | null, name: string): string =>
  `${category ?? "(без категорії)"}/${name}`;

export function diffChannels(actual: ActualChannel[], desired: ChannelConfig[]): DiffOp[] {
  const actualByKey = new Map(actual.map((c) => [channelKey(c.category, c.name), c]));
  const desiredKeys = new Set(desired.map((c) => channelKey(c.category, c.name)));

  const creates: DiffOp[] = [];
  const updates: DiffOp[] = [];

  for (const want of desired) {
    const key = channelKey(want.category, want.name);
    const have = actualByKey.get(key);
    if (have === undefined) {
      creates.push({ type: "create", entity: "channel", target: key });
      continue;
    }
    const fields: Record<string, FieldChange> = {};
    if (have.type !== want.type) fields["type"] = { from: have.type, to: want.type };
    const wantTopic = want.topic ?? null;
    if ((have.topic ?? null) !== wantTopic && want.type !== "GuildVoice") {
      fields["topic"] = { from: have.topic, to: wantTopic };
    }
    if (want.tags !== undefined && !setEq(have.tags ?? [], want.tags)) {
      fields["tags"] = { from: [...(have.tags ?? [])].sort(), to: [...want.tags].sort() };
    }
    if (!overwritesSatisfied(want.permissionOverwrites, have.permissionOverwrites)) {
      fields["permissionOverwrites"] = {
        from: have.permissionOverwrites,
        to: want.permissionOverwrites,
      };
    }
    if (Object.keys(fields).length > 0) {
      updates.push({ type: "update", entity: "channel", target: key, fields });
    }
  }

  const orphans: DiffOp[] = actual
    .filter((c) => !desiredKeys.has(channelKey(c.category, c.name)))
    .map(
      (c): DiffOp => ({
        type: "orphan",
        entity: "channel",
        target: channelKey(c.category, c.name),
      }),
    )
    .sort((a, b) => a.target.localeCompare(b.target));

  return [...creates, ...updates, ...orphans];
}

/** Повний diff: roles → categories → channels (порядок = порядок apply). */
export function diffAll(actual: ActualState, config: FullConfig): DiffOp[] {
  return [
    ...diffRoles(actual.roles, config.roles),
    ...diffCategories(actual.categories, config.categories),
    ...diffChannels(actual.channels, config.channels),
  ];
}
