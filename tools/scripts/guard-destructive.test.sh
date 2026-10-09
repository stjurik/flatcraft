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
# cwd = тимчасовий worktree (пропуск). Спільний стан репо (SHARED) — окремо: блок звідусіль.
FORMS=(
  'git reset --hard'
  'git reset --hard HEAD~1'
  'git clean -fd'
  'git clean -xfd'
  'git checkout -- x'
  'git checkout .'
  'git restore x'
  'git restore --staged --worktree .'
  'git worktree remove --force'
  'rm x'
  'rm -rf docs'
  "find . -name '*.tmp' -delete"
  'ls | xargs rm'
  'true; rm -rf docs'
  'bash -c "git reset --hard"'
)
# stash і гілки спільні для всіх worktree одного репо: з tmp-* вони руйнують і ~/hart.
SHARED=(
  'git stash drop'
  'git stash clear'
  'git branch -D feat/x'
  'git branch --delete --force feat/x'
)

# ─── 1. Форми з #216 у ~/hart — блок ───────────────────────────────────────
for c in "${FORMS[@]}" "${SHARED[@]}"; do expect блок "$HART" "$c"; done
expect блок "$HART" 'cd ~/hart && git checkout -- x'

# ─── 2. Постійний worktree ~/hart-wt/<гілка> — під тим самим захистом ─────
for c in "${FORMS[@]}" "${SHARED[@]}"; do expect блок "$PERM" "$c"; done

# ─── 3. Ті самі команди в тимчасовому worktree — пропуск ───────────────────
for c in "${FORMS[@]}"; do expect пропуск "$TMPWT" "$c"; done
expect пропуск "$TMPWT" 'cd ~/hart-wt/tmp-x && git checkout -- x'

# ─── 3а. Спільний стан репо — блок і з тимчасового worktree ────────────────
# Рішення yurii: «руйнівні в ~/hart — у будь-якій формі». Специфікація #216 дозволяла
# це в tmp-*, але stash і гілки спільні — з tmp-* це та сама шкода для ~/hart.
for c in "${SHARED[@]}"; do
  expect блок "$TMPWT" "$c"
  expect блок "$HART" "git -C ~/hart-wt/tmp-x ${c#git }"
done
expect блок "$TMPWT" 'git worktree remove ~/hart-wt/feat-y'
expect блок "$TMPWT" 'git worktree remove ../feat-y'
expect пропуск "$HART" 'git worktree remove ~/hart-wt/tmp-x'
expect пропуск "$TMPWT" 'git worktree remove ~/hart-wt/tmp-x'

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
блок|git -C ~/hart-wt/tmp-probe stash clear
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
for c in "${FORMS[@]}" "${SHARED[@]}"; do
  [[ "$c" == git\ * ]] || continue
  expect блок "$TMPWT" "git -C ~/hart ${c#git }"
done
for c in "${FORMS[@]}"; do
  [[ "$c" == git\ * ]] || continue
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

# ─── 10. Обходи з рецензії Flash на #218 (a1315f2) — кожен був пропуском ────
# Рядок: тека (hart|tmp)|очікування|команда — тека першою, щоб probe-profile-rules.sh
# не брав ці рядки за зразки сценарію 4 (контрприклади Sonnet #218, п.19).
while IFS='|' read -r where want cmd; do
  [[ "$where" == hart ]] && d="$HART" || d="$TMPWT"
  expect "$want" "$d" "$cmd"
done <<'EOF2'
hart|блок|cd /tmp | rm -rf docs
hart|блок|cd ~/hart-wt/tmp-x | git reset --hard
hart|блок|cd /tmp |& cat; true | rm -rf docs
hart|блок|cd /tmp & rm -rf docs
hart|блок|VAR=$(rm -rf docs)
hart|блок|export A=$(git reset --hard)
hart|блок|echo "$(rm -rf docs)"
hart|блок|echo "x`git checkout -- x`y"
hart|блок|env -S "git reset --hard"
hart|блок|env -S"rm -rf docs"
hart|блок|env --split-string="rm -rf docs"
tmp|блок|git worktree remove feat-y
tmp|блок|git worktree remove --force hart-wt/feat-y
tmp|блок|git worktree remove tmp-x
hart|пропуск|cd /tmp && echo ok | cat
tmp|пропуск|cd /tmp | true; rm -rf docs
hart|пропуск|A=$(git status)
hart|пропуск|echo "$(git log -1)"
hart|пропуск|env -S "git status"
tmp|пропуск|git worktree remove ~/hart-wt/tmp-x
EOF2

# ─── 11. Обходи з контрприкладів Sonnet 5.5 на #218 (ddc0399) ──────────────
# Рядок: тека|очікування|команда; у команді `\n` — перенос рядка, `\\` — зворотна
# риска (printf %b). Тека: hart, tmp або scratch.
while IFS='|' read -r where want raw; do
  case "$where" in hart) d="$HART" ;; tmp) d="$TMPWT" ;; *) d="$SCRATCH" ;; esac
  printf -v cmd '%b' "$raw"
  expect "$want" "$d" "$cmd"
done <<'EOF3'
hart|блок|git reset \\\n  --hard
hart|блок|rm -rf \\\n docs
hart|блок|ls # note\nrm -rf docs
hart|блок|[ $# -eq 0 ] && rm -rf docs
hart|блок|echo a#b; rm -rf docs
hart|блок|x=$(git rev-parse HEAD); git reset --hard "$x"
hart|блок|echo $(date); rm -rf docs
hart|блок|(true);rm -rf docs
hart|блок|true&&(rm -rf docs)
hart|блок|cat <(rm -rf docs)
hart|блок|echo $(date)\nrm -rf docs
hart|блок|(cd ~/hart-wt/tmp-x && pnpm test) && git reset --hard
hart|блок|x=$(cd ~/hart-wt/tmp-x && pwd) ; git reset --hard
hart|блок|x=rm; $x -rf docs
hart|блок|s=reset; git $s --hard
hart|блок|eval "$cmd"
hart|блок|bash -c "$cmd"
hart|блок|eval "$(echo rm -rf docs)"
hart|блок|function f { rm -rf docs; }; f
hart|блок|f(){ rm -rf docs; }; f
hart|блок|case x in x) rm -rf docs;; esac
hart|блок|git rm -rf docs
hart|блок|git switch -f HEAD
hart|блок|git switch --discard-changes HEAD
hart|блок|git checkout-index -a -f
hart|блок|git read-tree --reset -u HEAD
tmp|блок|git reflog expire --expire=now --all
hart|блок|printf x | xargs --max-procs 2 rm -f
hart|блок|echo docs | xargs -l rm -rf
hart|блок|nice --adjustment 5 rm -rf docs
hart|блок|time -p rm -rf docs
hart|блок|bash -O extglob -c 'rm -rf docs'
hart|блок|exec -a x rm -rf docs
hart|блок|setsid rm -rf docs
hart|блок|ionice -c 3 rm -rf docs
hart|блок|fish -c 'rm -rf docs'
hart|блок|find . -maxdepth 0 -exec git reset --hard \\;
scratch|блок|find -O3 ~/hart/docs -delete
tmp|блок|export GIT_DIR=$HOME/hart/.git GIT_WORK_TREE=$HOME/hart; git reset --hard
tmp|блок|export GIT_DIR=~/hart/.git; git reset --hard
tmp|блок|git -c core.worktree=~/hart reset --hard
scratch|блок|ln -s ~/hart ~/hart-wt/tmp-l && rm -rf ~/hart-wt/tmp-l/docs
scratch|блок|mv ~/hart ~/hart-wt/tmp-m && rm -rf ~/hart-wt/tmp-m
hart|блок|echo 'git reset --hard' | bash
hart|блок|bash <<< 'rm -rf docs'
scratch|блок|rm -f ~/.flatcraft/hooks/guard-destructive.sh
hart|блок|git reset --har
hart|блок|git branch --del --forc x
hart|блок|git restore --staged --wor x
hart|блок|cat <<EOF\n$(rm -rf docs)\nEOF
hart|блок|echo "<<X"\nrm -rf docs\nX
hart|пропуск|git commit -m "$(cat <<'EOF'\nfix: don't crash\nEOF\n)"
hart|пропуск|gh pr create --title x --body "$(cat <<'EOF'\nit's ok; rm -rf docs\nEOF\n)"
hart|пропуск|cat <<'EOF' > /tmp/x\nrm -rf docs\nEOF
hart|пропуск|x=$(git rev-parse HEAD); git log "$x"
hart|пропуск|(cd ~/hart-wt/tmp-x && git reset --hard)
hart|пропуск|find . -name x -exec grep y {} \\;
hart|пропуск|bash tools/scripts/x.test.sh
hart|пропуск|nice -n 5 git status
hart|пропуск|echo a#b
hart|пропуск|printf x | xargs --max-procs 2 echo
tmp|пропуск|ln -s ~/hart-wt/tmp-x/a ~/hart-wt/tmp-x/b && rm -f ~/hart-wt/tmp-x/c
EOF3

# ─── Мутанти: кожен механізм розбору тримається тестом (#216) ──────────────
mutant_names=() mutant_from=() mutant_to=()
mutant() { mutant_names+=("$1") mutant_from+=("$2") mutant_to+=("$3"); }
mutant 'контроль: копія без змін' '' ''
mutant 'розбір ланцюжків && ; | вимкнено' '        elif t in SEPS or t == ")":' '        elif False:'
mutant 'git -C не змінює ціль' 'cur = chdir(cur, args[i + 1])' 'pass'
mutant 'bash -c не розбирається' 'check(script, cwds, depth + 1)' 'pass'
mutant 'tmp-* не виняток (захищено все)' 'return not p[len(WT) + 1 :].split("/")[0].startswith("tmp-")' 'return True'
mutant 'спільний стан дозволено з tmp-*' '    if shared:' '    if False:'
mutant 'cd у конвеєрі змінює теку (Flash #218, 1)' $'        if new is not None and not subshell:\n            if sep == "&&":' $'        if new is not None:\n            if sep in ("&&", "|"):'
mutant 'VAR=$( — не підстановка (Flash #218, 2)' '(t == "(" and (not cur or cur[-1].endswith("$")))' '(t == "(" and (not cur or cur[-1] == "$"))'
mutant '"$(…)" у слові не розбирається (Flash #218, 2)' 'for inner in substitutions(t):' 'for inner in []:'
mutant 'env -S пропускає рядок (Flash #218, 3)' 'tokens = shlex.split(value) + tokens[after:]' 'tokens = tokens[after:]'
mutant 'worktree remove <ім'"'"'я> — від теки виклику (Flash #218, 4)' 'cur if os.path.isabs(p) or p == "~" or p.startswith("~/") else [None]' 'cur'
mutant '\\+перенос не склеюється (Sonnet #218, 1)' 'cmd.replace("\\\n", "")' 'cmd'
mutant '# — коментар (Sonnet #218, 2)' '    lx.commenters = ""' '    pass'
mutant 'склеєна пунктуація не розрізається (Sonnet #218, 3)' 'op = next(o for o in OPS + [t[i]] if t.startswith(o, i))' 'op = t[i:]'
mutant 'cd у ( … ) діє назовні (Sonnet #218, 4)' '            run(g, cur, depth + 1)  # підоболонка: її cd назовні не діє' '            cur = cur'
mutant 'невизначене слово команди — пропуск (Sonnet #218, 5)' $'    if not literal(tokens[0]):\n        undefined(' $'    if False:\n        undefined('
mutant '{ } не роздільники (Sonnet #218, 6)' 'SEPS = {"&&", "||", ";;&", ";;", ";&", "|", "|&", ";", "&", "\n", "{", "}"}' 'SEPS = {"&&", "||", ";;&", ";;", ";&", "|", "|&", ";", "&", "\n"}'
mutant 'git switch --discard-changes — пропуск (Sonnet #218, 7)' $'        what = "git switch --discard-changes"' $'        pass'
mutant 'reflog expire — не спільний стан (Sonnet #218, 7)' '        what, shared = f"git reflog {rest[0]}", True' '        pass'
mutant 'xargs --max-procs без значення (Sonnet #218, 8)' '                "--max-args", "--max-procs", "--max-chars", "--process-slot-var"}' '                "--max-args", "--max-chars", "--process-slot-var"}'
mutant 'обгортки без опцій (Sonnet #218, 9)' '            i = skip_opts(tokens, i + 1, WRAPPERS[base])' '            i += 1'
mutant 'find -exec <не rm> — пропуск (Sonnet #218, 10)' '            segment([t for t in cmd if t != "{}"], base, depth)' '            pass'
mutant 'export GIT_DIR не відстежується (Sonnet #218, 11)' $'            if eq and k in ("GIT_DIR", "GIT_WORK_TREE"):\n                SHELL_ENV[k] = v' $'            if False:\n                SHELL_ENV[k] = v'
mutant 'ln/mv у тій самій команді — без сліду (Sonnet #218, 12)' $'    if prog in ("ln", "mv"):\n        TAINT.extend(' $'    if False:\n        TAINT.extend('
mutant 'оболонка зі stdin — пропуск (Sonnet #218, 13)' '            undefined(f"{prog} читає команду з stdin", [], cwds)' '            pass'
mutant '~/.flatcraft не захищено (Sonnet #218, 14)' '    if under(p, HART) or under(p, FLAT):' '    if under(p, HART):'
mutant 'тіла heredoc — як команди (Sonnet #218, 15)' '    cmd = strip_heredocs(cmd.replace("\\\n", ""))' '    cmd = cmd.replace("\\\n", "")'
mutant 'скорочені довгі опції — пропуск' '    return any(a.startswith("--") and len(a) > 2 and name.startswith(a.split("=", 1)[0])' '    return any(a.split("=", 1)[0] == name'
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
