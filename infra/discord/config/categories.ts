import { CategoryConfigSchema, type CategoryConfig } from "./types.js";

// Gated-категорії: @everyone не бачить, відповідна interest-роль + Moderator —
// бачать. Founder має Administrator (обходить overwrites автоматично).
const gatedBy = (interestRole: string) => [
  { role: "@everyone", allow: [], deny: ["ViewChannel"] },
  { role: interestRole, allow: ["ViewChannel"], deny: [] },
  { role: "🟠 Moderator", allow: ["ViewChannel"], deny: [] },
];

export const CATEGORIES: CategoryConfig[] = CategoryConfigSchema.array().parse([
  { name: "📋 ІНФОРМАЦІЯ", position: 0 },
  { name: "💬 ЗАГАЛЬНЕ", position: 1 },
  { name: "🎨 ПРОЄКТУВАННЯ", position: 2 },
  { name: "🐛 ТЕХ-ПІДТРИМКА", position: 3, permissionOverwrites: gatedBy("🐛 interest/Support") },
  { name: "🏭 ВИРОБНИЦТВО", position: 4, permissionOverwrites: gatedBy("🏭 interest/Production") },
  { name: "📚 НАВЧАННЯ", position: 5, permissionOverwrites: gatedBy("📚 interest/Learning") },
  { name: "🎙️ ГОЛОСОВІ", position: 6 },
]);
