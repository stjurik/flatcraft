import { ChannelConfigSchema, type ChannelConfig } from "./types.js";

// Read-only для звичайних учасників: @everyone не пише, Moderator пише
// (Founder — Administrator, обходить overwrites).
const readOnly = [
  { role: "@everyone", allow: [], deny: ["SendMessages"] },
  { role: "🟠 Moderator", allow: ["SendMessages"], deny: [] },
];

export const CHANNELS: ChannelConfig[] = ChannelConfigSchema.array().parse([
  // ── 📋 ІНФОРМАЦІЯ ────────────────────────────────────────────────────────
  {
    name: "правила",
    type: "GuildText",
    category: "📋 ІНФОРМАЦІЯ",
    topic: "Правила спільноти UA — прочитай перед першим повідомленням.",
    permissionOverwrites: readOnly,
  },
  {
    name: "оголошення",
    type: "GuildAnnouncement",
    category: "📋 ІНФОРМАЦІЯ",
    topic: "Релізи, downtime, новини проєкту.",
    permissionOverwrites: readOnly,
  },
  {
    name: "welcome",
    type: "GuildText",
    category: "📋 ІНФОРМАЦІЯ",
    topic: "Вітання новим учасникам.",
  },
  {
    name: "ресурси",
    type: "GuildText",
    category: "📋 ІНФОРМАЦІЯ",
    topic: "Лінки: /about, ROADMAP, GitHub.",
    permissionOverwrites: readOnly,
  },
  // ── 💬 ЗАГАЛЬНЕ ──────────────────────────────────────────────────────────
  { name: "загальний-чат", type: "GuildText", category: "💬 ЗАГАЛЬНЕ" },
  {
    name: "показуй-проєкти",
    type: "GuildForum",
    category: "💬 ЗАГАЛЬНЕ",
    tags: ["готово", "у-процесі", "ідея"],
  },
  // ── 🎨 ПРОЄКТУВАННЯ ──────────────────────────────────────────────────────
  {
    name: "поради-з-проєктування",
    type: "GuildForum",
    category: "🎨 ПРОЄКТУВАННЯ",
    tags: [
      "material:steel",
      "material:aluminum",
      "material:stainless",
      "побут",
      "меблі",
      "виробництво",
    ],
  },
  { name: "підготовка-креслень", type: "GuildText", category: "🎨 ПРОЄКТУВАННЯ" },
  { name: "запит-нового-шаблону", type: "GuildText", category: "🎨 ПРОЄКТУВАННЯ" },
  // ── 🐛 ТЕХ-ПІДТРИМКА (gated: interest/Support — overwrite на категорії) ──
  {
    name: "bug-report",
    type: "GuildForum",
    category: "🐛 ТЕХ-ПІДТРИМКА",
    // Discord обмежує forum-tag 20 символами, тому "tpl:", не "template:"
    // ("template:perforated-panel" = 25 chars — API відхиляє).
    tags: [
      "severity:critical",
      "severity:high",
      "severity:medium",
      "severity:low",
      "status:open",
      "status:investigating",
      "status:fixed",
      "tpl:l-bracket",
      "tpl:z-bracket",
      "tpl:corner-angle",
      "tpl:wall-shelf",
      "tpl:perfo-panel",
    ],
  },
  { name: "помилки-валідації", type: "GuildText", category: "🐛 ТЕХ-ПІДТРИМКА" },
  { name: "feature-request", type: "GuildText", category: "🐛 ТЕХ-ПІДТРИМКА" },
  // ── 🏭 ВИРОБНИЦТВО (gated: interest/Production) ──────────────────────────
  { name: "вибір-виробника", type: "GuildText", category: "🏭 ВИРОБНИЦТВО" },
  {
    name: "виробники-офіційно",
    type: "GuildText",
    category: "🏭 ВИРОБНИЦТВО",
    topic: "Пишуть лише верифіковані виробники; читають усі.",
    permissionOverwrites: [
      { role: "@everyone", allow: [], deny: ["SendMessages"] },
      { role: "🟢 Verified-Manufacturer", allow: ["SendMessages"], deny: [] },
    ],
  },
  { name: "k-фактор-і-допуски", type: "GuildText", category: "🏭 ВИРОБНИЦТВО" },
  // ── 📚 НАВЧАННЯ (gated: interest/Learning) ───────────────────────────────
  { name: "для-новачків", type: "GuildText", category: "📚 НАВЧАННЯ" },
  {
    name: "туторіали",
    type: "GuildText",
    category: "📚 НАВЧАННЯ",
    permissionOverwrites: readOnly,
  },
  // ── 🎙️ ГОЛОСОВІ ──────────────────────────────────────────────────────────
  { name: "Voice — Загальний", type: "GuildVoice", category: "🎙️ ГОЛОСОВІ" },
  { name: "Voice — Office-hours", type: "GuildVoice", category: "🎙️ ГОЛОСОВІ" },
]);
