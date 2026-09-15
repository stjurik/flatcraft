#!/usr/bin/env bash
# trust-worktree.test.sh — набір для trust-worktree.sh.
#
# ЧОМУ ЦЕЙ НАБІР ІСНУЄ. Вимір 2026-09-14 (Стадія 0, `docs/19` §D.4) показав, що
# `agy` довіряє теці лише за ТОЧНИМ збігом шляху кореня git, а не за префіксом:
#   trustedWorkspaces = [~/hart-wt]            , cwd = ~/hart-wt/a8-stage-0 → браузерний OAuth
#   trustedWorkspaces = [~/hart-wt/a8-stage-0] , cwd = ~/hart-wt/a8-stage-0 → exit 0 PASS
# Обидва варіанти опитування PR #108 («додати батьківську теку» / «тримати
# worktree всередині ~/hart») спираються саме на префіксне успадкування, якого
# немає. Тому реєстрація мусить бути ПОТОЧНОЮ, а не разовою правкою конфігу —
# і найдорожчий тест тут §7: він фіксує, що батьківський запис НЕ вважається
# довірою. Якщо колись поведінка `agy` зміниться, впаде саме цей рядок.
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/trust-worktree.sh"
TMP_ROOT="$(mktemp -d)"
FAILED=0
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  echo "✗ $1"
  [[ $# -gt 1 ]] && echo "   $2"
  FAILED=1
}

# make_settings — мінімальний settings.json з двома сторонніми ключами:
# їх недоторканість перевіряється окремо (скрипт не має права переписати конфіг).
make_settings() {
  local path="$1"
  shift
  local entries=""
  for e in "$@"; do entries="${entries:+$entries, }\"$e\""; done
  cat >"$path" <<EOF
{
  "model": "Gemini 3.1 Pro (High)",
  "permissions": { "allow": ["read_file(*)", "write_file(*)"] },
  "trustedWorkspaces": [$entries]
}
EOF
}

make_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email t@e.st
  git -C "$dir" config user.name t
  echo "$(realpath "$dir")"
}

run() { AGY_SETTINGS="$SETTINGS" bash "$SCRIPT" "$@"; }

# expect_code — негативні перевірки звіряють ТОЧНИЙ код, а не «щось ненульове».
# Інакше відсутній скрипт (127) читається як «правильно відмовив», і набір
# зеленіє на порожньому місці — рівно той фолс-грін, що коштував PR #108 прогону CI.
expect_code() {
  local want="$1" name="$2"
  shift 2
  local out got=0
  out="$(run "$@" 2>&1)" || got=$?
  if [[ "$got" -eq "$want" ]]; then
    echo "✓ $name"
  else
    fail "$name — код $got, очікував $want" "$out"
  fi
}

entries() {
  python3 -c "import json,sys;print('\n'.join(json.load(open(sys.argv[1]))['trustedWorkspaces']))" "$SETTINGS"
}

# ── 1. add → check ─────────────────────────────────────────────────────────
SETTINGS="$TMP_ROOT/s1.json"
make_settings "$SETTINGS"
REPO="$(make_repo "$TMP_ROOT/wt1")"
run add "$REPO" >/dev/null 2>&1 || fail "add → ненульовий код"
if run check "$REPO" >/dev/null 2>&1; then
  echo "✓ add → check: тека стає довіреною"
else
  fail "add → check: тека не стала довіреною"
fi

# ── 2. add ідемпотентний ───────────────────────────────────────────────────
run add "$REPO" >/dev/null 2>&1
COUNT="$(entries | grep -cxF "$REPO")"
if [[ "$COUNT" -eq 1 ]]; then
  echo "✓ add двічі → один запис (ідемпотентність)"
else
  fail "add двічі → записів: $COUNT, очікував 1"
fi

# ── 3. сторонні ключі недоторкані ──────────────────────────────────────────
if python3 -c "
import json,sys
d=json.load(open(sys.argv[1]))
assert d['model']=='Gemini 3.1 Pro (High)', d.get('model')
assert d['permissions']['allow']==['read_file(*)','write_file(*)'], d.get('permissions')
" "$SETTINGS" 2>/dev/null; then
  echo "✓ сторонні ключі settings.json збережені"
else
  fail "add зіпсував model/permissions — скрипт не має права їх чіпати"
fi

# ── 4. remove → check падає ────────────────────────────────────────────────
run remove "$REPO" >/dev/null 2>&1 || fail "remove → ненульовий код"
expect_code 1 "remove → тека більше не довірена" check "$REPO"

# ── 5. remove ідемпотентний (повторний виклик не падає) ────────────────────
if run remove "$REPO" >/dev/null 2>&1; then
  echo "✓ remove двічі → 0 (ідемпотентність)"
else
  fail "повторний remove дав ненульовий код"
fi

# ── 6. add реєструє КОРІНЬ git, а не підтеку ───────────────────────────────
# Інакше autorun.sh зареєстрував би, скажімо, apps/web, і `agy` знову впав би
# у браузерний OAuth — з вигляду «проблема логіна».
mkdir -p "$REPO/apps/web"
run add "$REPO/apps/web" >/dev/null 2>&1
if entries | grep -qxF "$REPO" && ! entries | grep -qxF "$REPO/apps/web"; then
  echo "✓ add з підтеки реєструє корінь git, не підтеку"
else
  fail "add з підтеки зареєстрував не корінь" "$(entries | tr '\n' ' ')"
fi
run remove "$REPO" >/dev/null 2>&1

# ── 7. батьківський запис НЕ дає довіри (вимір 2026-09-14) ─────────────────
SETTINGS="$TMP_ROOT/s7.json"
PARENT="$TMP_ROOT/parent"
CHILD="$(make_repo "$PARENT/child")"
make_settings "$SETTINGS" "$(realpath "$PARENT")"
expect_code 1 "батьківський запис не вважається довірою (вимір §D.4)" check "$CHILD"

# ── 8. немає файлу налаштувань → 2, файл не створюється ────────────────────
SETTINGS="$TMP_ROOT/absent.json"
OUT="$(run add "$CHILD" 2>&1)"
CODE=$?
if [[ "$CODE" -eq 2 ]] && [[ ! -e "$SETTINGS" ]]; then
  echo "✓ немає settings.json → exit 2, файл не створюється"
else
  fail "немає settings.json → код $CODE (очікував 2) або файл створено" "$OUT"
fi

# ── 9. зіпсований JSON → 2, файл не переписується ──────────────────────────
SETTINGS="$TMP_ROOT/broken.json"
printf '{ це не json' >"$SETTINGS"
BEFORE="$(cat "$SETTINGS")"
run add "$CHILD" >/dev/null 2>&1
CODE=$?
if [[ "$CODE" -eq 2 ]] && [[ "$(cat "$SETTINGS")" == "$BEFORE" ]]; then
  echo "✓ зіпсований JSON → exit 2, файл не переписано"
else
  fail "зіпсований JSON → код $CODE (очікував 2) або файл змінено"
fi

# ── 10. check не потребує git-репозиторію для чужого шляху ─────────────────
# autorun.sh кличе check ДО того, як worktree існує — відповідь має бути
# «не довірена», а не падіння.
SETTINGS="$TMP_ROOT/s10.json"
make_settings "$SETTINGS"
expect_code 1 "неіснуюча тека → не довірена (без падіння)" check "$TMP_ROOT/ще-не-створено"

# ── 11. autorun.sh СПРАВДІ кличе реєстрацію ────────────────────────────────
# Найдорожчий розрив цього проєкту — «код + тест, 0 викликів у пайплайні»
# (інспекція §A: `validateSheet`, `validateHoles`). Зелені кейси 1-10 доводять,
# що скрипт працює, і НЕ доводять, що ним хтось користується. Цей кейс і є
# різниця між «функція протестована» і «інваріант enforced»: порядок важливий —
# реєстрація до першого виклику `agy`, тобто після `git worktree add`.
AUTORUN="$(dirname "$SCRIPT")/autorun.sh"
if [[ ! -f "$AUTORUN" ]]; then
  fail "немає autorun.sh — перевірити підключення неможливо"
else
  # Закомічений рядок — НЕ виклик. Перша версія цього кейсу грепала весь файл і
  # зеленіла на `# DISABLED: ...trust-worktree.sh add...` — тобто пропускала рівно
  # той спосіб зламати інваріант, який найімовірніший (хтось «тимчасово» вимикає
  # рядок). Тому рядки-коментарі відсіюються до порівняння порядку.
  code_line() {
    grep -nE "$1" "$AUTORUN" | grep -vE '^[0-9]+:[[:space:]]*#' | head -1 | cut -d: -f1
  }
  WT_ADD_LINE="$(code_line 'worktree add')"
  TRUST_LINE="$(code_line 'trust-worktree\.sh"? add')"
  if [[ -z "$TRUST_LINE" ]]; then
    fail "autorun.sh не кличе trust-worktree.sh add — worktree лишиться недовіреним для agy"
  elif [[ -z "$WT_ADD_LINE" ]] || [[ "$TRUST_LINE" -lt "$WT_ADD_LINE" ]]; then
    fail "autorun.sh кличе trust-worktree.sh ДО створення worktree (рядки: add=$WT_ADD_LINE, trust=$TRUST_LINE)"
  else
    echo "✓ autorun.sh реєструє worktree після worktree add (інваріант, не лише код)"
  fi
fi

if [[ "$FAILED" -eq 0 ]]; then
  echo "Усі тести пройдено."
else
  echo "Є падіння."
  exit 1
fi
