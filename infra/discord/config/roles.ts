import { RoleConfigSchema, type RoleConfig } from "./types.js";

// 3-axis таксономія (3-OSI). Parse при імпорті — невалідний config падає
// на першому ж тесті/запуску, а не посеред apply.
export const ROLES: RoleConfig[] = RoleConfigSchema.array().parse([
  // ── authority: ієрархічні права ─────────────────────────────────────────
  {
    name: "🔴 Founder",
    axis: "authority",
    color: 0xed4245,
    hoist: true,
    permissions: ["Administrator"],
    position: 100,
  },
  {
    name: "🟠 Moderator",
    axis: "authority",
    color: 0xf39c12,
    hoist: true,
    permissions: ["ManageMessages", "KickMembers", "MuteMembers", "ModerateMembers"],
    position: 90,
  },
  {
    name: "🟢 Verified-Manufacturer",
    axis: "authority",
    color: 0x57f287,
    hoist: true,
    permissions: [
      "SendMessages",
      "AttachFiles",
      "EmbedLinks",
      "AddReactions",
      "ReadMessageHistory",
    ],
    position: 80,
  },
  {
    name: "⚪ Member",
    axis: "authority",
    color: 0x99aab5,
    hoist: false,
    permissions: [
      "SendMessages",
      "ReadMessageHistory",
      "AddReactions",
      "AttachFiles",
      "EmbedLinks",
    ],
    position: 10,
  },
  // ── selfid: само-ідентифікація через onboarding (без власних прав) ──────
  {
    name: "💡 i-am/DIY",
    axis: "selfid",
    color: 0x3498db,
    hoist: false,
    permissions: [],
    position: 5,
  },
  {
    name: "🏢 i-am/Business",
    axis: "selfid",
    color: 0x9b59b6,
    hoist: false,
    permissions: [],
    position: 5,
  },
  {
    name: "🛠️ i-am/Engineer",
    axis: "selfid",
    color: 0x1abc9c,
    hoist: false,
    permissions: [],
    position: 5,
  },
  {
    name: "🏭 i-am/Manufacturer",
    axis: "selfid",
    color: 0xe67e22,
    hoist: false,
    permissions: [],
    position: 5,
  },
  // ── interest: opt-in доступ до gated-категорій (через overwrites) ───────
  {
    name: "🐛 interest/Support",
    axis: "interest",
    color: 0x95a5a6,
    hoist: false,
    permissions: [],
    position: 1,
  },
  {
    name: "🎨 interest/Design",
    axis: "interest",
    color: 0x95a5a6,
    hoist: false,
    permissions: [],
    position: 1,
  },
  {
    name: "🏭 interest/Production",
    axis: "interest",
    color: 0x95a5a6,
    hoist: false,
    permissions: [],
    position: 1,
  },
  {
    name: "📚 interest/Learning",
    axis: "interest",
    color: 0x95a5a6,
    hoist: false,
    permissions: [],
    position: 1,
  },
]);
