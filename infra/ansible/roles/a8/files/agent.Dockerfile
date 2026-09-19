# Образ агента A8 — node:22 + Claude Code + uv.
#
# ЧОМУ ОКРЕМИЙ ОБРАЗ (рішення yurii 2026-09-18, Q2-г). Демон запускає агента
# через a8-run-agent, а в node:22 немає ні `claude`, ні `uv`: на хості вони
# стоять під agent у ~/.local (звірено read-only 2026-09-19:
# ~/.local/lib/node_modules/@anthropic-ai/claude-code, версія 2.1.272; uv у
# ~/.local/bin). Монтувати хостову інсталяцію в контейнер означало б, що вміст
# контейнера залежить від ручної правки на машині; Dockerfile у git — ні.
#
# Версії ПІНОВАНІ і збігаються з виміряними на A8: claude-code 2.1.272 — та,
# на якій виміряні М-1…М-4 (PR #110). uv 0.12.17 — тег перевірено в
# ghcr.io (200; контрольний неіснуючий тег — 404), 2026-09-19.
# Базовий node:22 — той самий тег, на якому пройшли виміри №6 і №7 (git у
# ньому є — виміри його використовували).
#
# Збирає роль при apply (`docker build`), тег містить обидві версії — зміна
# версії = новий тег = нова збірка, стара лишається для відкату.
ARG UV_VERSION=0.12.17
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM node:22
ARG CLAUDE_CODE_VERSION=2.1.272
RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
 && npm cache clean --force
COPY --from=uv /uv /uvx /usr/local/bin/
# Користувача НЕ задаємо: UID визначає a8-run-agent (`--user 1002:1002`),
# бо він мусить збігатися з власником репо на хості (вимір №6).
