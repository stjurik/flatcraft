import { ServerConfigSchema, type ServerConfig } from "./types.js";

export const SERVER: ServerConfig = ServerConfigSchema.parse({
  name: "hart.crimea.ua",
  // Low = verified email (вимога Community-фічі і так його вмикає).
  verificationLevel: "Low",
  // OnlyMentions: не спамити нотифікаціями кожним повідомленням.
  defaultMessageNotifications: "OnlyMentions",
  systemChannel: "welcome",
});
