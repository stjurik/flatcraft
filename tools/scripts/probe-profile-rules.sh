#!/usr/bin/env bash
# probe-profile-rules.sh — зразки команд проти профілю оркестратора на СПРАВЖНЬОМУ
# Claude Code, а не на емуляції.
#
# ЧОМУ ЦЕ ІСНУЄ. Сценарій 31 install-orchestrator-profile.test.sh звіряє зразки з
# профілем емуляцією правил за документацією — у CI справжнього Claude Code немає, а
# емуляція — лише прочитання документації. Правило вже раз не діяло, як написано:
# `Bash(git push * :*)` мав забороняти `git push origin :гілка`, але Claude Code читає
# кінцеве `:*` як стару форму префікса (2026-09-28; не побачили ні автор, ні дві
# рецензії). Тому після кожної зміни профілю — цей замір: той самий перелік зразків,
# справжній механізм дозволів.
#
# ЯК. Для кожного зразка — свіжа `claude -p` (haiku) у порожній тимчасовій теці, у
# режимі dontAsk, з deny/ask профілю через --settings і allow через --allowedTools.
# Модель просять виконати рівно цю команду; результат береться з події tool_result:
#   deny  — «Permission to use Bash with command … has been denied» (спрацювало deny);
#   allow — команда виконалась;
#   ask/питає — «… don't ask mode» (ask і «немає правила» dontAsk не розрізняє).
# git, gh, pnpm, npx та інші програми з переліку STUBS підмінено заглушками, тож
# навіть якщо правило не спрацює, нічого справжнього не станеться.
#
# ЧОГО НЕ ДОВОДИТЬ: режим Auto (там замість «don't ask» — класифікатор); обгортки й
# складені команди — зразки прості. Витрачає ліміт підписки: ~45 коротких викликів.
# Не в CI — запускати вручну після зміни профілю.
#
# Використання: bash tools/scripts/probe-profile-rules.sh [модель]   (за замовчуванням haiku)
# exit 0 — усі зразки як очікувано; exit 1 — розбіжність; exit 2 — не запустився.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
PROFILE="$ROOT/.claude/settings.orchestrator.json"
TEST="$ROOT/tools/scripts/install-orchestrator-profile.test.sh"
MODEL="${1:-haiku}"
STUBS=(git gh pnpm npx node tsx uv uvx docker sudo ssh scp curl ansible-playbook agy)
command -v claude >/dev/null || {
  echo "відмова: claude не знайдено" >&2
  exit 2
}

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/ws"
for s in "${STUBS[@]}"; do
  printf '#!/bin/sh\necho "stub %s $*"\n' "$s" >"$W/bin/$s"
  chmod +x "$W/bin/$s"
done
jq '{permissions: {deny: .permissions.deny, ask: .permissions.ask}}' "$PROFILE" >"$W/deny-ask.json"
mapfile -t ALLOW < <(jq -r '.permissions.allow[]' "$PROFILE")
# Зразки — ті самі, що в сценарії 31 тесту: одне джерело, щоб емуляція й замір не розійшлись.
grep -E '^(deny|allow|ask|питає)\|' "$TEST" >"$W/samples.txt"
[[ -s "$W/samples.txt" ]] || {
  echo "відмова: у $TEST немає зразків" >&2
  exit 2
}

probe() { # probe <№> <команда> → рядок «deny|allow|ask/питає|?» у $W/<№>.got
  local n="$1" cmd="$2" raw used res
  raw="$W/$n.raw"
  (cd "$W/ws" && PATH="$W/bin:$PATH" timeout 150 claude -p \
    "Use the Bash tool exactly once to run this exact command, verbatim, then stop and reply DONE. Command: $cmd" \
    --model "$MODEL" --tools Bash --permission-mode dontAsk --no-session-persistence \
    --settings "$W/deny-ask.json" --allowedTools "${ALLOW[@]}" \
    --output-format stream-json --verbose </dev/null >"$raw" 2>/dev/null)
  used="$(jq -rR 'fromjson? | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .input.command' "$raw" | head -1)"
  res="$(jq -rR 'fromjson? | select(.type=="user") | .message.content[]? | select(.type=="tool_result")
    | (.content | if type=="array" then map(.text // "") | join(" ") else tostring end)' "$raw" | head -1)"
  if [[ "$used" != "$cmd" ]]; then
    echo "?|модель виконала не те: «$used»" >"$W/$n.got"
  elif [[ "$res" == "Permission to use Bash with command"* ]]; then
    echo "deny|" >"$W/$n.got"
  elif [[ "$res" == *"don't ask mode"* ]]; then
    echo "ask/питає|" >"$W/$n.got"
  else
    echo "allow|" >"$W/$n.got"
  fi
}

n=0
while IFS='|' read -r _ cmd; do
  n=$((n + 1))
  probe "$n" "$cmd" &
  while (($(jobs -rp | wc -l) >= 6)); do wait -n; done
done <"$W/samples.txt"
wait

fail=0
n=0
while IFS='|' read -r want cmd; do
  n=$((n + 1))
  IFS='|' read -r got why <"$W/$n.got"
  if [[ "$got" == "$want" || ("$got" == "ask/питає" && ("$want" == ask || "$want" == питає)) ]]; then
    echo "✓ $want → $got: $cmd"
  else
    echo "✗ очікував $want, вийшло $got: $cmd ${why:+— $why}"
    fail=1
  fi
done <"$W/samples.txt"
echo "Claude Code $(claude --version 2>/dev/null | head -1), модель $MODEL, зразків: $n"
((fail)) && {
  echo "РОЗБІЖНІСТЬ — профіль поводиться не так, як заявлено"
  exit 1
}
echo "Усі зразки — як очікувано."
