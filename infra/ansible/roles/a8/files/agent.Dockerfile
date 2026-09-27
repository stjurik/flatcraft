# Образ агента A8 — node:22 + Claude Code + uv + системні бібліотеки CadQuery.
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
# Збирає роль при apply (`docker build`). Тег містить версії claude-code, uv і
# pnpm: зміна версії = новий тег, старий образ лишається під своїм тегом для
# відкату. Зміна САМОГО Dockerfile (як apt-шар нижче) тегу не міняє: образ
# перезбирається під тим самим тегом, а старий лишається без тегу
# (`docker images -f dangling=true`). Відкат тоді — git revert і повторне
# застосування ролі.
ARG UV_VERSION=0.12.17
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM node:22
ARG CLAUDE_CODE_VERSION=2.1.272
ARG PNPM_VERSION=9.12.0
RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
 && npm cache clean --force
# pnpm — інакше перший же крок тіку падає. У node:22 є corepack, але шимів він
# не створює: їх робить `corepack enable`. Без них `pnpm` немає в PATH, і
# entrypoint образу (`node:22` docker-entrypoint.sh) підставляє `node` перед
# невідомою командою — `pnpm install` стає `node pnpm install`, а node шукає
# файл `pnpm` у робочій теці:
#   Error: Cannot find module '/home/agent/hart-wt/<id>/pnpm'
# Саме це впіймав перший тік на A8 2026-09-19 (задача log-pr116, detail=deps).
#
# `prepare … --activate` завантажує pnpm НА ЕТАПІ ЗБІРКИ, а не при першому
# запуску: інакше кожен холодний контейнер ходив би в мережу по менеджер
# пакетів, і це ламалось би рівно тоді, коли ввімкнуть egress-фільтр.
# Версія збігається з `packageManager` у package.json і PNPM_VERSION у ci.yml —
# розбіжність означала б, що агент збирає не те, що потім перевіряє CI.
RUN corepack enable \
 && corepack prepare "pnpm@${PNPM_VERSION}" --activate
COPY --from=uv /uv /uvx /usr/local/bin/
# Системні бібліотеки CadQuery / OCP. `uv sync` ставить Python-пакети, але не
# .so, яких потребує cadquery-ocp: без libGL.so.1 імпорт падає, і оракул воркера
# `uv run --directory workers/cad pytest tests/templates/test_registry.py` на A8
# давав rc=2 (handoff 2026-09-23 §2 п.1). Перелік — той самий, що в runtime-стадії
# infra/docker/cad-worker.Dockerfile (обидва образи на Debian bookworm): агент
# ганяє тести воркера на тих самих бібліотеках, що й прод. Паритет тримає
# інваріант 9 у tools/scripts/check-ansible-a8.sh, живу поведінку — V18.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libgl1 libglu1-mesa libxrender1 libxext6 libxi6 libsm6 libfontconfig1 \
 && rm -rf /var/lib/apt/lists/*
# Користувача НЕ задаємо: UID визначає a8-run-agent (`--user 1002:1002`),
# бо він мусить збігатися з власником репо на хості (вимір №6).
