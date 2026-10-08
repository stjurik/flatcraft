#!/usr/bin/env bash
# guard-destructive.test.sh — оракул #216: хук PreToolUse блокує руйнівні git- і
# rm-команди в ~/hart і постійних worktree в будь-якій формі, а в ~/hart-wt/tmp-*
# пропускає.
#
# Що СПРАВЖНЄ: сам хук; подія — JSON того самого вигляду, що подає Claude Code
# (`tool_name`, `tool_input.command`, `cwd`); вердикт — код виходу (2 — блок, 0 — пропуск).
# Що ПІДМІНЕНО: HOME — тимчасова тека з `hart/`, `hart-wt/tmp-x/`, `hart-wt/feat-y/`
# і `scratch/`; жодна команда не виконується, хук лише читає її рядок.
# Мутанти (наприкінці): набір проганяється проти зламаних копій хука
# (GUARD_UNDER_TEST) і мусить упасти на кожній.
#
# Рядки `блок|…` і `пропуск|…` у сценарії 4 читає й probe-profile-rules.sh — ті самі
# зразки на справжньому Claude Code з реальним HOME.
# Запуск: bash tools/scripts/guard-destructive.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${GUARD_UNDER_TEST:-$HERE/guard-destructive.sh}"
fail=0
T="$(mktemp -d)"
M=""
trap 'rm -rf "$T" ${M:+"$M"}' EXIT
T="$(cd "$T" && pwd -P)"
mkdir -p "$T/hart/docs" "$T/hart-wt/tmp-x/docs" "$T/hart-wt/feat-y/docs" "$T/scratch/out"
touch "$T/hart/x" "$T/hart-wt/tmp-x/x" "$T/hart-wt/feat-y/x"
HART="$T/hart" TMPWT="$T/hart-wt/tmp-x" PERM="$T/hart-wt/feat-y" SCRATCH="$T/scratch"

ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
  # Під мутантом досить першого провалу: мутанта вбито.
  [[ -z "${GUARD_UNDER_TEST:-}" ]] || exit 1
}

# hook <cwd|-> <команда> → код виходу хука; stderr — у $T/err. «-» — подія без cwd.
hook() {
  local ev
  if [[ "$1" == - ]]; then
    ev="$(jq -n --arg c "$2" '{tool_name: "Bash", tool_input: {command: $c}}')"
  else
    ev="$(jq -n --arg c "$2" --arg d "$1" '{tool_name: "Bash", tool_input: {command: $c}, cwd: $d}')"
  fi
  HOME="$T" bash "$SCRIPT" <<<"$ev" >/dev/null 2>"$T/err"
}
expect() { # expect <блок|пропуск> <cwd> <команда>
  local want="$1" cwd="$2" cmd="$3" rc
  hook "$cwd" "$cmd"
  rc=$?
  local where="${cwd/#$T/\~}"
  if [[ "$want" == блок ]]; then
    if [[ $rc == 2 ]] && grep -q 'guard-destructive: заблоковано' "$T/err"; then
      ok "блок [$where]: $cmd"
    else
      bad "НЕ заблоковано (rc=$rc) [$where]: $cmd — $(<"$T/err")"
    fi
  else
    [[ $rc == 0 ]] && ok "пропуск [$where]: $cmd" || bad "заблоковано зайве (rc=$rc) [$where]: $cmd — $(<"$T/err")"
  fi
}

# Форми з #216. Кожна — з cwd = ~/hart (блок), з cwd = постійний worktree (блок) і з
# cwd = тимчасовий worktree (пропуск).
FORMS=(
  'git reset --hard'
  'git reset --hard HEAD~1'
  'git clean -fd'
  'git clean -xfd'
  'git checkout -- x'
  'git checkout .'
  'git restore x'
  'git restore --staged --worktree .'
  'git stash drop'
  'git stash clear'
  'git branch -D feat/x'
  'git worktree remove --force'
  'rm x'
  'rm -rf docs'
  "find . -name '*.tmp' -delete"
  'ls | xargs rm'
  'true; rm -rf docs'
  'bash -c "git reset --hard"'
)

# ─── 1. Форми з #216 у ~/hart — блок ───────────────────────────────────────
for c in "${FORMS[@]}"; do expect блок "$HART" "$c"; done
expect блок "$HART" 'cd ~/hart && git checkout -- x'

# ─── 2. Постійний worktree ~/hart-wt/<гілка> — під тим самим захистом ─────
for c in "${FORMS[@]}"; do expect блок "$PERM" "$c"; done

# ─── 3. Ті самі команди в тимчасовому worktree — пропуск ───────────────────
for c in "${FORMS[@]}"; do expect пропуск "$TMPWT" "$c"; done
expect пропуск "$TMPWT" 'cd ~/hart-wt/tmp-x && git checkout -- x'

# ─── 4. Ціль задано в самій команді: cwd нейтральний (scratch) ─────────────
# Ці рядки читає й probe-profile-rules.sh: там HOME справжній, тож `~/hart` — це
# справжнє дерево, а git і rm підмінено заглушками. Шляхи для rm — неіснуючі.
while IFS='|' read -r want cmd; do
  expect "$want" "$SCRATCH" "$cmd"
done <<'EOF'
блок|git -C ~/hart reset --hard
блок|git -C ~/hart clean -fd
блок|git -C ~/hart checkout -- probe-no-such-file
блок|git -C ~/hart restore probe-no-such-file
блок|git -C ~/hart stash clear
блок|git -C ~/hart branch -D probe-no-such-branch
блок|cd ~/hart && git checkout -- probe-no-such-file
блок|true; rm -rf ~/hart/probe-no-such-dir
блок|bash -c "git -C ~/hart reset --hard"
блок|find ~/hart/probe-no-such-dir -delete
пропуск|git -C ~/hart-wt/tmp-probe reset --hard
пропуск|git -C ~/hart-wt/tmp-probe checkout -- probe-no-such-file
пропуск|rm -rf ~/hart-wt/tmp-probe/probe-no-such-dir
пропуск|git -C ~/hart status
EOF

# ─── 5. `git -C ~/hart …` з будь-якого cwd — блок; `git -C tmp-x` з ~/hart — пропуск
for c in "${FORMS[@]}"; do
  [[ "$c" == git\ * ]] || continue
  expect блок "$TMPWT" "git -C ~/hart ${c#git }"
  expect пропуск "$HART" "git -C ~/hart-wt/tmp-x ${c#git }"
done

# ─── 6. Неруйнівні команди в ~/hart — пропуск ──────────────────────────────
for c in 'git status' 'git diff' 'git checkout -b x' 'git worktree add ~/hart-wt/tmp-x' \
  'git log --oneline -3' 'git restore --staged x' 'git clean -n' 'git branch -d feat/x' \
  'git worktree remove --force ~/hart-wt/tmp-x' 'ls docs' 'cat x | head'; do
  expect пропуск "$HART" "$c"
done

# ─── 7. rm у scratchpad сесії — пропуск ────────────────────────────────────
expect пропуск "$SCRATCH" 'rm -rf out'
expect пропуск "$HART" "rm -rf $SCRATCH/out"
expect пропуск "$HART" "cd $SCRATCH && rm -rf out"

# ─── 8. Невизначена ціль — захищена (fail closed) ──────────────────────────
expect блок "$TMPWT" 'rm -rf "$DIR"'
expect блок "$TMPWT" 'rm -rf ~/hart-wt/*'
expect блок "$TMPWT" 'rm -rf ~'
expect блок "$TMPWT" 'rm -rf ../feat-y'
expect блок "$TMPWT" 'cd - && rm -rf docs'
expect блок - 'rm -rf docs'
expect блок "$TMPWT" 'git worktree remove --force ~/hart-wt/feat-y'
expect блок "$TMPWT" 'cd ~/hart-wt/tmp-x; git reset --hard; cd ~/hart && rm x'
expect блок "$HART" 'cd ~/hart-wt/tmp-x || rm -rf docs'
expect блок "$HART" 'echo $(rm -rf docs)'
expect блок "$HART" 'timeout 5 env A=1 rm -rf docs'
expect блок "$HART" 'find . -exec rm {} \;'
expect блок "$HART" 'git checkout -f main'
expect пропуск - 'git status'

# ─── 9. Нерозібрана подія — блок, а не пропуск ─────────────────────────────
rc=0
HOME="$T" bash "$SCRIPT" <<<'не json' >/dev/null 2>&1 || rc=$?
[[ $rc == 2 ]] && ok "нерозібраний JSON події → блок (2)" || bad "нерозібраний JSON → rc=$rc"
rc=0
HOME="$T" bash "$SCRIPT" <<<'{"tool_name":"Read","tool_input":{"file_path":"x"}}' >/dev/null 2>&1 || rc=$?
[[ $rc == 0 ]] && ok "не-Bash подія — пропуск" || bad "не-Bash подія → rc=$rc"
expect блок "$HART" 'echo "незакрита лапка'

# ─── Мутанти: кожен механізм розбору тримається тестом (#216) ──────────────
mutant_names=() mutant_from=() mutant_to=()
mutant() { mutant_names+=("$1") mutant_from+=("$2") mutant_to+=("$3"); }
mutant 'контроль: копія без змін' '' ''
mutant 'розбір ланцюжків && ; | вимкнено' 'if t and set(t) <= set(";&|\n`"):' 'if False:'
mutant 'git -C не змінює ціль' 'cur = chdir(cur, args[i + 1])' 'pass'
mutant 'bash -c не розбирається' 'check(script, cwds, depth + 1)' 'pass'
mutant 'tmp-* не виняток (захищено все)' 'return not p[len(ROOTS[1]) + 1 :].split("/")[0].startswith("tmp-")' 'return True'
mutant 'невизначена ціль — пропуск' $'        if p is None:\n            return True' $'        if p is None:\n            return False'
if [[ -z "${GUARD_UNDER_TEST:-}" && "$fail" -eq 0 ]]; then
  M="$(mktemp -d)"
  src="$(<"$SCRIPT")"
  for i in "${!mutant_names[@]}"; do
    from="${mutant_from[$i]}" m="$src"
    if [[ -n "$from" ]]; then
      rest="${src#*"$from"}"
      if [[ "$rest" == "$src" || "$rest" == *"$from"* ]]; then
        bad "мутант «${mutant_names[$i]}»: текст не знайдено рівно один раз — мутація застаріла"
        continue
      fi
      m="${src/"$from"/"${mutant_to[$i]}"}"
    fi
    printf '%s\n' "$m" >"$M/$i.sh"
    GUARD_UNDER_TEST="$M/$i.sh" bash "$HERE/$(basename "$0")" >"$M/$i.out" 2>&1
    rc=$?
    killer="$(grep -m1 '^✗ ' "$M/$i.out")"
    if ((i == 0)); then
      [[ $rc == 0 ]] && ok "мутації: контроль — незмінена копія проходить увесь набір" ||
        bad "мутації: контроль упав (rc=$rc): ${killer#✗ }"
    elif [[ $rc == 1 && -n "$killer" ]]; then
      ok "мутанта вбито: ${mutant_names[$i]} ← ${killer#✗ }"
    else
      bad "мутант ВИЖИВ: ${mutant_names[$i]} (rc=$rc)"
    fi
  done
fi

if [[ "$fail" -eq 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
