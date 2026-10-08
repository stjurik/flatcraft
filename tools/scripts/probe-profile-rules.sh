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
# ЯК. Для кожного зразка — свіжа `claude -p` у порожній тимчасовій теці, у режимі
# dontAsk, з deny/ask профілю через --settings. Модель просять виконати рівно цю
# команду; результат — з події tool_result:
#   deny     — «Permission to use Bash with command … has been denied»;
#   виконано — без відмови;
#   dontAsk  — «… don't ask mode»: немає allow, або спрацювало ask.
# Один прогін доводить лише deny. Решта — з контролем (рецензія #141, 2026-09-28):
#   allow — ще прогін БЕЗ allow профілю: команда не мусить виконатись. Інакше вона
#           проходить і без правила (вбудовані read-only: `git status`, `git log`), і
#           зразок нічого не доводить;
#   ask   — ще прогін, де сама команда є в allow: ask мусить перемогти (порядок
#           deny → ask → allow). Без ask-правила команда виконалась би;
#   питає — той самий прогін: команда мусить виконатись — ні deny, ні ask на ній немає.
#   блок  — хук guard-destructive.sh (#216) у налаштуваннях, а команда — в allow: хук
#           мусить заблокувати («хук»). Контроль — той самий прогін без хука: команда
#           мусить виконатись, інакше блок дав щось інше, а не хук;
#   пропуск — хук у налаштуваннях, команда в allow: мусить виконатись.
# Зразки блок/пропуск — з guard-destructive.test.sh (сценарій 4). Хук запускається з
# робочого дерева, де лежить ця проба, через --settings тимчасового файла — профіль і
# копію в ~/.flatcraft/hooks проба не чіпає. HOME справжній: `~/hart` у зразку — це
# справжнє дерево, тому rm, find і xargs теж підмінено, а шляхи в зразках — неіснуючі.
# Зразок, де модель виконала не ту команду («?»), повторюється один раз.
# git, gh, pnpm, npx та інші програми з переліку STUBS підмінено заглушками, тож
# навіть якщо правило не спрацює, нічого справжнього не станеться.
#
# ВЕРСІЯ ВАЖИТЬ. Той самий профіль на різних версіях Claude Code поводиться по-різному:
# `Bash(git push * :**)` діє з 2.1.282, а на 2.1.280–2.1.281 — ні (виміряно 2026-09-28).
# Проба міряє той бінарник, що в CLAUDE_BIN (за замовчуванням — `claude` з PATH), і
# друкує його версію. Сесія оркестратора у VS Code працює на бінарнику розширення, а
# не на CLI з PATH, — міряйте той, що справді працює.
#
# ЧОГО НЕ ДОВОДИТЬ: режим Auto (там замість «don't ask» — класифікатор); обгортки й
# складені команди — зразки профілю прості (складені є лише серед зразків хука); що
# встановлена копія хука в ~/.flatcraft/hooks та сама — це звіряє
# `install-orchestrator-profile.sh --check`. Витрачає ліміт підписки: ~95 коротких викликів.
# Не в CI — запускати вручну після зміни профілю чи оновлення Claude Code.
#
# Використання: [CLAUDE_BIN=<шлях>] bash tools/scripts/probe-profile-rules.sh [модель]   (модель — haiku)
# exit 0 — усі зразки як очікувано; exit 1 — розбіжність; exit 2 — не запустився.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
PROFILE="$ROOT/.claude/settings.orchestrator.json"
TEST="$ROOT/tools/scripts/install-orchestrator-profile.test.sh"
GUARD_TEST="$ROOT/tools/scripts/guard-destructive.test.sh"
GUARD="$ROOT/tools/scripts/guard-destructive.sh"
MODEL="${1:-haiku}"
BIN="${CLAUDE_BIN:-claude}"
STUBS=(git gh pnpm npx node tsx uv uvx docker sudo ssh scp curl ansible-playbook agy rm find xargs)
VERSION="$("$BIN" --version 2>/dev/null | head -1)" || true
[[ -n "$VERSION" ]] || {
  echo "відмова: $BIN не запускається" >&2
  exit 2
}
echo "Бінарник: $(command -v "$BIN"), $VERSION"
[[ -n "${CLAUDE_BIN:-}" ]] ||
  echo "  (CLAUDE_BIN не задано — міряю claude з PATH; сесія у VS Code може мати іншу версію)"

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/ws"
for s in "${STUBS[@]}"; do
  printf '#!/bin/sh\necho "stub %s $*"\n' "$s" >"$W/bin/$s"
  chmod +x "$W/bin/$s"
done
jq '{permissions: {deny: .permissions.deny, ask: .permissions.ask}}' "$PROFILE" >"$W/deny-ask.json"
jq --arg c "bash \"$GUARD\"" '. + {hooks: {PreToolUse: [{matcher: "Bash",
  hooks: [{type: "command", command: $c, timeout: 10}]}]}}' "$W/deny-ask.json" >"$W/deny-ask-hook.json"
mapfile -t ALLOW < <(jq -r '.permissions.allow[]' "$PROFILE")
# Зразки — ті самі, що в сценарії 31 тесту: одне джерело, щоб емуляція й замір не розійшлись.
grep -E '^(deny|allow|ask|питає)\|' "$TEST" >"$W/samples.txt"
[[ -s "$W/samples.txt" ]] || {
  echo "відмова: у $TEST немає зразків" >&2
  exit 2
}
grep -E '^(блок|пропуск)\|' "$GUARD_TEST" >>"$W/samples.txt" || {
  echo "відмова: у $GUARD_TEST немає зразків блок|пропуск" >&2
  exit 2
}

run_once() { # run_once <файл-результату> <команда> <allow: profile|none|profile+cmd|hook+cmd|cmd>
  local out="$1" cmd="$2" mode="$3" raw="$1.raw" used res allow=() settings="$W/deny-ask.json" part
  case "$mode" in
  profile) allow=("${ALLOW[@]}") ;;
  profile+cmd) allow=("${ALLOW[@]}" "Bash($cmd)") ;;
  none) allow=() ;;
  hook+cmd | cmd)
    # Складену команду Claude Code перевіряє по частинах — у allow кожна частина.
    allow=("${ALLOW[@]}" "Bash($cmd)")
    while IFS= read -r part; do
      [[ -n "$part" ]] && allow+=("Bash($part)")
    done < <(sed -E 's/ *(&&|\|\||;|\|) */\n/g' <<<"$cmd")
    [[ "$mode" == hook+cmd ]] && settings="$W/deny-ask-hook.json"
    ;;
  esac
  (cd "$W/ws" && PATH="$W/bin:$PATH" timeout 150 "$BIN" -p \
    "Use the Bash tool exactly once to run this exact command, verbatim, then stop and reply DONE. Command: $cmd" \
    --model "$MODEL" --tools Bash --permission-mode dontAsk --no-session-persistence \
    --settings "$settings" ${allow[@]+--allowedTools "${allow[@]}"} \
    --output-format stream-json --verbose </dev/null >"$raw" 2>/dev/null)
  used="$(jq -rR 'fromjson? | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .input.command' "$raw" | head -1)"
  res="$(jq -rR 'fromjson? | select(.type=="user") | .message.content[]? | select(.type=="tool_result")
    | (.content | if type=="array" then map(.text // "") | join(" ") else tostring end)' "$raw" | head -1)"
  if [[ "$used" != "$cmd" ]]; then
    echo "?" >"$out"
  elif [[ "$res" == *"guard-destructive: заблоковано"* ]]; then
    echo "хук" >"$out"
  elif [[ "$res" == "Permission to use Bash with command"* ]]; then
    echo "deny" >"$out"
  elif [[ "$res" == *"don't ask mode"* ]]; then
    echo "dontAsk" >"$out"
  else
    echo "виконано" >"$out"
  fi
}
run() { # run — те саме, з одним повтором, якщо модель виконала не ту команду
  run_once "$@"
  [[ "$(<"$1")" == "?" ]] && run_once "$@"
  return 0
}

n=0
while IFS='|' read -r want cmd; do
  n=$((n + 1))
  case "$want" in
  блок)
    run "$W/$n.a" "$cmd" hook+cmd &
    run "$W/$n.b" "$cmd" cmd &
    ;;
  пропуск) run "$W/$n.a" "$cmd" hook+cmd & ;;
  *) run "$W/$n.a" "$cmd" profile & ;;
  esac
  case "$want" in
  allow) run "$W/$n.b" "$cmd" none & ;;
  ask | питає) run "$W/$n.b" "$cmd" profile+cmd & ;;
  esac
  while (($(jobs -rp | wc -l) >= 6)); do wait -n; done
done <"$W/samples.txt"
wait

fail=0
n=0
while IFS='|' read -r want cmd; do
  n=$((n + 1))
  a="$(<"$W/$n.a")"
  b="—"
  [[ -f "$W/$n.b" ]] && b="$(<"$W/$n.b")"
  case "$want" in
  deny) expect_a=deny expect_b="—" ;;
  allow) expect_a=виконано expect_b=dontAsk ;;
  ask) expect_a=dontAsk expect_b=dontAsk ;;
  питає) expect_a=dontAsk expect_b=виконано ;;
  блок) expect_a=хук expect_b=виконано ;;
  пропуск) expect_a=виконано expect_b="—" ;;
  esac
  if [[ "$a" == "$expect_a" && "$b" == "$expect_b" ]]; then
    echo "✓ $want: $cmd"
  else
    echo "✗ $want: $cmd — профіль: $a (треба $expect_a), контроль: $b (треба $expect_b)"
    fail=1
  fi
done <"$W/samples.txt"
echo "$VERSION, модель $MODEL, зразків: $n"
((fail)) && {
  echo "РОЗБІЖНІСТЬ — профіль на цій версії поводиться не так, як заявлено"
  exit 1
}
echo "Усі зразки — як очікувано."
