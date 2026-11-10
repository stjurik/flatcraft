#!/usr/bin/env bash
# a8-git-lib.test.sh — правила ігнору, яким вірить перевірка чистоти дерева (#302 B).
#
# trusted_ignore_rules бере правила лише з .gitignore коміту (не з дерева агента,
# не з .git/info/exclude). Тут — те, чого не видно зі сценаріїв тіку (3 — з
# рецензії #315: info/attributes і порядок «identity перед симлінками»):
#   1. переписування вкладеного .gitignore від кореня (D/**/шаблон, D/шаблон, «!»);
#   2. СПРАВЖНІ правила цього репозиторію ігнорують кеші, які пишуть інструменти
#      lefthook, CI і тести (ruff, mypy, hypothesis, pytest, uv, pnpm, turbo, tsc).
#      Ruff, mypy і hypothesis ховаються самі — `.gitignore` з «*» у своїй теці
#      (виміряно: ruff 0.17.4, mypy 2.4.1, hypothesis 6.170.15), — а такому
#      правилу перевірка не вірить. Без рядків у кореневому
#      .gitignore кожна задача A8 з комітом Python падала б як «брудна».
#
# Запуск: tools/scripts/a8-git-lib.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
fail=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
}

# shellcheck source=tools/scripts/a8-git-lib.sh
source "$HERE/a8-git-lib.sh"

# ─── 1. Переписування від кореня ─────────────────────────────────────────────
r="$tmp/r"
git init -q -b main "$r"
printf 'node_modules/\n*.pyc\n' >"$r/.gitignore"
mkdir -p "$r/tools" "$r/apps/web"
printf '# коментар\n\ncache/\n/build\nsub/out.txt\n*.log\n!keep.log\n' >"$r/tools/.gitignore"
echo x >"$r/apps/web/a.ts"
git -C "$r" add -A && git -C "$r" -c user.email=t@t -c user.name=t commit -qm base
export A8_REPO_DIR="$r" A8_KILL_SWITCH="$tmp/STOP"
rules="$tmp/rules"
if trusted_ignore_rules HEAD "$rules"; then
  want='node_modules/
*.pyc
tools/**/cache/
tools/build
tools/sub/out.txt
tools/**/*.log
!tools/**/keep.log'
  [[ "$(cat "$rules")" == "$want" ]] && ok "правила вкладеного .gitignore переписано від кореня (D/**/…, D/…, «!»), коментарі й порожні рядки — геть" ||
    bad "правила: $(tr '\n' '|' <"$rules")"
else
  bad "trusted_ignore_rules HEAD → ненуль"
fi
# Ті самі правила в ls-files: що ховається, а що — ні.
mkdir -p "$r/tools/a/cache" "$r/other/cache" "$r/tools/build" "$r/tools/x/build" "$r/tools/sub"
for f in tools/a/cache/c other/cache/c tools/build/b tools/x/build/b tools/sub/out.txt tools/z.log tools/keep.log x.log apps/web/node_modules/m.js; do
  mkdir -p "$r/$(dirname "$f")" && echo 1 >"$r/$f"
done
got="$(GIT_INDEX_FILE="$r/.git/index" git -C "$r" ls-files -o --exclude-from="$rules" | LC_ALL=C sort | tr '\n' ' ')"
[[ "$got" == "other/cache/c tools/keep.log tools/x/build/b x.log " ]] &&
  ok "ls-files з цими правилами: вкладене діє лише під своєю текою, «!» повертає файл" || bad "ls-files: [$got]"
untracked_outside_rules "$r" "$r/.git/index" "$rules" "$tmp/out" &&
  [[ "$(tr '\0' ' ' <"$tmp/out")" == "other/cache/c tools/keep.log tools/x/build/b x.log " ]] &&
  ok "untracked_outside_rules: той самий перелік через hgit, NUL-розділений" || bad "untracked_outside_rules: [$(tr '\0' ' ' <"$tmp/out" 2>/dev/null)]"
trusted_ignore_rules no-such-commit "$tmp/r2" 2>/dev/null && bad "коміту немає, а правила «прочитано»" ||
  ok "коміту немає → ненуль (fail closed)"

# ─── 2. Справжні правила цього репозиторію ───────────────────────────────────
# Не напряму в клоні репозиторію: у CI checkout мілкий (.git/shallow), і hgit
# на ньому справедливо відмовляє. Тож .gitignore-файли HEAD (звичайним git, лише
# читання) — у тимчасовий репозиторій, і trusted_ignore_rules — уже на ньому.
g="$tmp/g"
git init -q -b main "$g"
while IFS= read -r -d '' p; do
  [[ "$p" == .gitignore || "$p" == */.gitignore ]] || continue
  mkdir -p "$g/$(dirname "$p")" && git -C "$REPO_ROOT" show "HEAD:$p" >"$g/$p"
done < <(git -C "$REPO_ROOT" ls-tree -r -z --name-only HEAD)
git -C "$g" add -A && git -C "$g" -c user.email=t@t -c user.name=t commit -qm gi
export A8_REPO_DIR="$g"
if trusted_ignore_rules HEAD "$tmp/repo-rules" 2>/dev/null; then
  s="$tmp/s"
  git init -q "$s"
  for f in workers/cad/.ruff_cache/0.17.4/x workers/cad/.mypy_cache/3.12/x.json workers/cad/.pytest_cache/v/x \
    workers/cad/.hypothesis/constants/x \
    workers/cad/.venv/bin/python workers/cad/flatcraft_cad/__pycache__/m.cpython-312.pyc \
    node_modules/.pnpm/x apps/web/node_modules/x .turbo/cookies/x apps/web/.turbo/x apps/web/tsconfig.tsbuildinfo \
    apps/web/.next/x apps/web/test-results/x coverage/x; do
    mkdir -p "$s/$(dirname "$f")" && echo 1 >"$s/$f"
  done
  printf '*\n' >"$s/workers/cad/.ruff_cache/.gitignore"
  printf '*\n' >"$s/workers/cad/.mypy_cache/.gitignore"
  printf '*\n' >"$s/workers/cad/.hypothesis/.gitignore"
  mkdir -p "$s/workers/cad/tests" && echo evil >"$s/workers/cad/tests/conftest_extra.py"
  got="$(git -C "$s" ls-files -o --exclude-from="$tmp/repo-rules" | LC_ALL=C sort | tr '\n' ' ')"
  [[ "$got" == "workers/cad/tests/conftest_extra.py " ]] &&
    ok "правила репо ігнорують кеші ruff, mypy, hypothesis, pytest, uv, pnpm, turbo, tsc, next, playwright — і не ховають решту" ||
    bad "правила репо пропускають кеші (бруд на кожній задачі A8) або ховають файл: [$got]"
else
  bad "trusted_ignore_rules HEAD у репозиторії → ненуль"
fi

# ─── 3. git_unsafe_reason: атрибути, sparse, config.worktree; порядок (рецензія #315)
u="$tmp/u"
git init -q -b main "$u"
git -C "$u" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
export A8_REPO_DIR="$u"
git_snapshot=""
[[ -z "$(git_unsafe_reason)" ]] && ok "чистий .git → причини немає" || bad "чистий .git: $(git_unsafe_reason)"
for f in info/attributes info/sparse-checkout config.worktree; do
  mkdir -p "$u/.git/$(dirname "$f")" && printf '* ident\n' >"$u/.git/$f"
  why="$(git_unsafe_reason)"
  [[ "$why" == ".git/$f існує"* ]] && ok ".git/$f → «.git/$f існує…»" || bad ".git/$f: «$why»"
  rm -f "$u/.git/$f"
done
# Підміна .git (новий inode) із симлінком усередині: identity — раніше за симлінк.
snapshot_git
mv "$u/.git" "$u/.git.old" && mkdir "$u/.git" && cp -a "$u/.git.old/." "$u/.git/"
ln -s "$tmp/victim" "$u/.git/FETCH_HEAD"
why="$(git_unsafe_reason)"
[[ "$why" == *"змінили identity"* ]] && ok "підміна .git із симлінком → «змінили identity» (STOP), а не «містить симлінк»" ||
  bad "порядок перевірок: «$why»"
git_snapshot=""
why="$(git_unsafe_reason)"
[[ "$why" == ".git містить симлінк FETCH_HEAD"* ]] && ok "без знімка — той самий симлінк → «.git містить симлінк FETCH_HEAD»" || bad "симлінк: «$why»"

if [[ "$fail" -eq 0 ]]; then
  echo "a8-git-lib: усі перевірки пройдено"
else
  echo "a8-git-lib: є падіння" >&2
fi
exit "$fail"
