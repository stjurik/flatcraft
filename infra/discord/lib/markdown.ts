import type { ActualOverwrite, ActualState } from "./diff.js";

// Snapshot → людиночитний doc (docs/discord-config/README.md).
// СВІДОМО без timestamp: однаковий стан → байт-у-байт однаковий файл,
// тож weekly GH Action комітить лише при реальному drift'і.

const esc = (s: string): string => s.replaceAll("|", "\\|").replaceAll("\n", " ");

const hex = (color: number): string => `#${color.toString(16).padStart(6, "0")}`;

function table(header: string[], rows: string[][]): string {
  const line = (cells: string[]) => `| ${cells.join(" | ")} |`;
  return [line(header), line(header.map(() => "---")), ...rows.map((r) => line(r.map(esc)))].join(
    "\n",
  );
}

function overwriteRows(target: string, overwrites: ActualOverwrite[]): string[][] {
  return overwrites.map((ow) => [
    target,
    ow.role,
    ow.allow.join(", ") || "—",
    ow.deny.join(", ") || "—",
  ]);
}

export function renderSnapshotMarkdown(state: ActualState, meta: { guildName: string }): string {
  const parts: string[] = [
    `# Discord — ${meta.guildName}`,
    "",
    "> Авто-згенеровано `pnpm discord:snapshot` (infra/discord, ADR-023).",
    "> НЕ редагувати вручну — зміни вносяться у `infra/discord/config/*.ts`.",
    "",
    "## Ролі",
    "",
  ];

  parts.push(
    table(
      ["Роль", "Колір", "Hoist", "Position", "Managed", "Permissions"],
      state.roles.map((r) => [
        r.name,
        hex(r.color),
        r.hoist ? "✓" : "",
        String(r.position),
        r.managed ? "✓" : "",
        r.permissions.join(", ") || "—",
      ]),
    ),
    "",
    "## Категорії та канали",
    "",
  );

  const renderChannels = (categoryName: string | null): string => {
    const channels = state.channels.filter((ch) => ch.category === categoryName);
    if (channels.length === 0) return "_(порожньо)_";
    return table(
      ["Канал", "Тип", "Topic", "Теги"],
      channels.map((ch) => [ch.name, ch.type, ch.topic ?? "—", ch.tags?.join(", ") ?? "—"]),
    );
  };

  for (const cat of state.categories) {
    parts.push(`### ${cat.name}`, "", renderChannels(cat.name), "");
  }
  if (state.channels.some((ch) => ch.category === null)) {
    parts.push("### (без категорії)", "", renderChannels(null), "");
  }

  const matrix = [
    ...state.categories.flatMap((c) =>
      overwriteRows(`категорія ${c.name}`, c.permissionOverwrites),
    ),
    ...state.channels.flatMap((ch) => overwriteRows(`#${ch.name}`, ch.permissionOverwrites)),
  ];
  parts.push(
    "## Permission-overwrites",
    "",
    matrix.length === 0 ? "_(немає)_" : table(["Ціль", "Роль", "Allow", "Deny"], matrix),
    "",
  );

  return parts.join("\n");
}
