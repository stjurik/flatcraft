import { PermissionFlagsBits } from "discord.js";
import { z } from "zod";

// Permissions у config'і — масиви ІМЕН флагів (не bigint): JSON-серіалізовні,
// людиночитні у PR-diff. У bigint конвертує lib/permissions.ts на API-boundary.
export const PermissionFlagSchema = z
  .string()
  .refine((name) => name in PermissionFlagsBits, {
    message: "Unknown Discord permission flag (див. PermissionFlagsBits у discord.js)",
  })
  .transform((name) => name as keyof typeof PermissionFlagsBits);

export type PermissionFlag = z.infer<typeof PermissionFlagSchema>;

// 3-axis таксономія ролей (3-OSI):
//  - authority: ієрархічні права (Founder → Member)
//  - selfid: само-ідентифікація через onboarding (i-am/*)
//  - interest: opt-in доступ до gated-категорій (interest/*)
export const RoleAxisSchema = z.enum(["authority", "selfid", "interest"]);
export type RoleAxis = z.infer<typeof RoleAxisSchema>;

export const RoleConfigSchema = z.object({
  name: z.string().min(1).max(100),
  axis: RoleAxisSchema,
  color: z.number().int().min(0).max(0xffffff),
  hoist: z.boolean(),
  permissions: z.array(PermissionFlagSchema),
  // Ordering intent: більше = вище у списку. Discord переприсвоює абсолютні
  // позиції при вставці, тому diff порівнює ВІДНОСНИЙ порядок, не числа.
  position: z.number().int().min(0),
});

export type RoleConfig = z.infer<typeof RoleConfigSchema>;

export const PermissionOverwriteConfigSchema = z.object({
  // Ім'я ролі з config/roles.ts або літерал "@everyone".
  role: z.string().min(1),
  allow: z.array(PermissionFlagSchema),
  deny: z.array(PermissionFlagSchema),
});

export type PermissionOverwriteConfig = z.infer<typeof PermissionOverwriteConfigSchema>;

export const CategoryConfigSchema = z.object({
  name: z.string().min(1).max(100),
  // Порядок зверху вниз: 0 — найвища категорія.
  position: z.number().int().min(0),
  permissionOverwrites: z.array(PermissionOverwriteConfigSchema).default([]),
});

export type CategoryConfig = z.infer<typeof CategoryConfigSchema>;

// Підтримуємо лише типи, які реально вживає config (мапінг у discord.js
// ChannelType — у scripts/). GuildAnnouncement і GuildForum потребують
// Community-фічі сервера (manual ToS-крок у MANUAL_SETUP.md).
export const ChannelKindSchema = z.enum([
  "GuildText",
  "GuildAnnouncement",
  "GuildForum",
  "GuildVoice",
]);

export type ChannelKind = z.infer<typeof ChannelKindSchema>;

export const ChannelConfigSchema = z
  .object({
    name: z.string().min(1).max(100),
    type: ChannelKindSchema,
    // Ім'я категорії з config/categories.ts.
    category: z.string().min(1),
    topic: z.string().max(1024).optional(),
    // Forum-теги; лише для GuildForum (refine нижче).
    tags: z.array(z.string().min(1).max(20)).max(20).optional(),
    permissionOverwrites: z.array(PermissionOverwriteConfigSchema).default([]),
  })
  .refine((ch) => ch.tags === undefined || ch.type === "GuildForum", {
    message: "tags дозволені лише для GuildForum-каналів",
  });

export type ChannelConfig = z.infer<typeof ChannelConfigSchema>;

export const ServerConfigSchema = z.object({
  name: z.string().min(2).max(100),
  verificationLevel: z.enum(["None", "Low", "Medium", "High", "VeryHigh"]),
  defaultMessageNotifications: z.enum(["AllMessages", "OnlyMentions"]),
  // Ім'я каналу для system messages (welcome). Optional: не задано — не чіпаємо.
  systemChannel: z.string().optional(),
});

export type ServerConfig = z.infer<typeof ServerConfigSchema>;

export interface FullConfig {
  roles: RoleConfig[];
  categories: CategoryConfig[];
  channels: ChannelConfig[];
}

const EVERYONE = "@everyone";

/**
 * Крос-файлова цілісність config'у (те, що Zod-схеми поодинці не бачать):
 * дублікати імен, посилання на неіснуючі категорії/ролі в overwrites.
 * Повертає список помилок; порожній — config консистентний.
 */
export function validateConfigIntegrity(config: FullConfig): string[] {
  const errors: string[] = [];

  const roleNames = new Set<string>();
  for (const role of config.roles) {
    if (roleNames.has(role.name)) errors.push(`Дублікат ролі: ${role.name}`);
    roleNames.add(role.name);
  }

  const categoryNames = new Set<string>();
  for (const cat of config.categories) {
    if (categoryNames.has(cat.name)) errors.push(`Дублікат категорії: ${cat.name}`);
    categoryNames.add(cat.name);
  }

  const channelKeys = new Set<string>();
  for (const ch of config.channels) {
    const key = `${ch.category}/${ch.name}`;
    if (channelKeys.has(key)) errors.push(`Дублікат каналу: ${key} (${ch.name})`);
    channelKeys.add(key);

    if (!categoryNames.has(ch.category)) {
      errors.push(`Канал ${ch.name} посилається на неіснуючу категорію: ${ch.category}`);
    }
  }

  const overwriteSources: { owner: string; overwrites: PermissionOverwriteConfig[] }[] = [
    ...config.categories.map((c) => ({
      owner: `категорія ${c.name}`,
      overwrites: c.permissionOverwrites,
    })),
    ...config.channels.map((c) => ({
      owner: `канал ${c.name}`,
      overwrites: c.permissionOverwrites,
    })),
  ];
  for (const { owner, overwrites } of overwriteSources) {
    for (const ow of overwrites) {
      if (ow.role !== EVERYONE && !roleNames.has(ow.role)) {
        errors.push(`${owner}: overwrite посилається на неіснуючу роль: ${ow.role}`);
      }
    }
  }

  return errors;
}
