#!/usr/bin/env bash
# check-agy-headless.test.sh — unit-прогін класифікатора D.4.
#
# Кожен рядок таблиці вердиктів (`docs/19` §D.4) — окремий тест проти
# фальшивого `agy`-стаба у PATH. Реальний прогін зачіпає ОДНУ гілку з восьми;
# решта сім перевіряються лише тут, тому наприкінці стоїть мутаційна перевірка:
# зламаний класифікатор МУСИТЬ завалити цей файл. Інакше «зелений» нічого не
# означав би (докладно про цей клас розриву — `docs/16` §1).
#
# Запуск: tools/scripts/check-agy-headless.test.sh
set -euo pipefail

SCRIPT_REAL="$(cd "$(dirname "$0")" && pwd)/check-agy-headless.sh"
TMP="$(realpath "$(mktemp -d)")"
trap 'rm -rf "$TMP"' EXIT

# ── Фальшивий `agy` ────────────────────────────────────────────────────────
# Імітує кожну гілку таблиці. Шляхи дістає з аргументів так само, як це робив
# би справжній CLI: вхідний/вихідний файл — з тексту промпту, лог — з --log-file.
mkdir -p "$TMP/bin"
cat >"$TMP/bin/agy" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
log=""; prompt=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --log-file) log="$2"; shift 2 ;;
    -p|--print) prompt="$2"; shift 2 ;;
    *) shift ;;
  esac
done
in_file="$(grep -oE '/[^ ]*_agy-probe-input\.md' <<<"$prompt" | head -1)"
out_file="$(grep -oE '/[^ ]*_agy-probe-output\.md' <<<"$prompt" | head -1)"
nonce=""
[[ -r "$in_file" ]] && nonce="$(sed -n 's/^NONCE=//p' "$in_file" | head -1)"

case "${STUB_MODE:-pass}" in
  pass)        printf '%s\n' "$nonce" >"$out_file" ;;
  soft_deny)   printf 'soft-denying tool confirmation "Bash"\n' >>"$log"
               echo "Завершено без результату." ;;
  login)       echo "Please sign in: https://accounts.google.com/o/oauth2/auth?client_id=x" ;;
  unauthorized) echo "Error: 401 Unauthorized — invalid bearer token"; exit 1 ;;
  hang)        sleep 5 ;;
  no_nonce)    printf 'Я прочитав файл, але значення не знайшов.\n' >"$out_file" ;;
  scope_creep) printf '%s\n' "$nonce" >"$out_file"
               printf 'agy сам вирішив переписати цей файл\n' >"$STUB_REPO/docs/15_LLM_PROMPTS.md" ;;
  no_output)   : ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/agy"

# ── Пісочниця: репозиторій + фальшивий HOME із trustedWorkspaces ───────────
setup_sandbox() {
  # Роздільні `local`: у `local a="$1" b="$TMP/$a"` вираз для b розкривається ДО
  # присвоєння a, тобто підхоплює `a` з ОБГОРТКИ (динамічна область видимості
  # bash). Саме на цьому тест спершу впав — теки називались іменами тестів.
  local name="$1" trusted="${2:-yes}"
  local root="$TMP/$name"
  rm -rf "$root"
  mkdir -p "$root/repo/docs/promts/inputs" "$root/home/.gemini/antigravity-cli"
  git -C "$root/repo" init -q -b main
  git -C "$root/repo" config user.email t@example.com
  git -C "$root/repo" config user.name test
  # Початковий коміт — щоб пісочниця була як справжнє дерево: `docs/promts/inputs/`
  # трекований, і git НЕ схлопує неторкані файли в один рядок `?? docs/`.
  : >"$root/repo/docs/promts/inputs/.gitkeep"
  git -C "$root/repo" add -A
  git -C "$root/repo" commit -qm "базовий стан пісочниці"
  local trustlist='"/zovsim/insha/tecka"'
  [[ "$trusted" == yes ]] && trustlist="\"$root/repo\""
  cat >"$root/home/.gemini/antigravity-cli/settings.json" <<EOF
{"model":"Gemini","permissions":{"allow":["read_file(*)","write_file(*)"]},"trustedWorkspaces":[$trustlist]}
EOF
  printf '%s\n' "$root"
}

# ── Прогін усього набору проти вказаного скрипта ───────────────────────────
# Виведений набір використовується двічі: для справжнього скрипта і для
# мутованих копій. Повертає 0, якщо всі очікування збіглись.
run_suite() {
  local script="$1" fail=0 sandbox_n=0

  # check <назва> <очікуваний-exit> <STUB_MODE> <trusted?> [аргументи скрипта...]
  check() {
    local name="$1" expected="$2" mode="$3" trusted="$4"
    shift 4
    local root actual=0
    root="$(setup_sandbox "sb$((++sandbox_n))" "$trusted")"
    (
      cd "$root/repo"
      HOME="$root/home" PATH="$TMP/bin:$PATH" STUB_MODE="$mode" STUB_REPO="$root/repo" \
        "$script" "$@" >"$TMP/out.txt" 2>&1
    ) || actual=$?
    if [[ "$actual" -eq "$expected" ]]; then
      echo "  ✓ $name"
    else
      echo "  ✗ $name — очікував exit $expected, отримав $actual"
      sed 's/^/      /' "$TMP/out.txt"
      fail=1
    fi
    # Транзитні файли зонда не мають лишатись у дереві.
    if [[ "$mode" != no_output ]] && compgen -G "$root/repo/docs/promts/inputs/_agy-probe-*" >/dev/null; then
      echo "  ✗ $name — транзитні файли зонда не прибрано"
      fail=1
    fi
  }

  # Рядок таблиці 1: nonce у вихідному файлі → PASS.
  check "nonce на місці → 0 (PASS)" 0 pass yes
  # Рядок 2: інструменти заблоковані allow-list'ом, НЕ логіном.
  check "soft-denying у лозі → 1" 1 soft_deny yes
  # Рядок 3: потрібен браузер.
  check "URL логіна у виводі → 2" 2 login yes
  # Рядок 4: креденшали недійсні.
  check "401 / invalid bearer → 3" 3 unauthorized yes
  # Рядок 5: таймаут (потрібен саме `timeout`, звідси exit 124 всередині).
  check "зависання → 4 (таймаут)" 4 hang yes --timeout 1
  # Рядок 6: відповів, але завдання не виконав.
  check "файл є, nonce немає → 5" 5 no_nonce yes
  # Рядок 6-bis: файлу немає взагалі — той самий клас «не виконав».
  check "вихідного файлу немає → 5" 5 no_output yes
  # Рядок 7: scope-creep — повторення інциденту Master Run 8.
  check "запис поза inputs/ → 6" 6 scope_creep yes
  # Рядок 8: робоча тека поза trustedWorkspaces — відмова ДО витрати виклику.
  check "недовірена тека → 7" 7 pass no

  return "$fail"
}

# ── Основний прогін ────────────────────────────────────────────────────────
echo "── класифікатор проти фальшивого agy"
suite_fail=0
run_suite "$SCRIPT_REAL" || suite_fail=1

# ── Мутаційна перевірка ────────────────────────────────────────────────────
# Ламаємо по одному впізнавачу і вимагаємо, щоб набір ПОЧЕРВОНІВ. Якщо
# мутація проходить незамічено — відповідна гілка не перевіряється насправді.
echo "── мутаційна перевірка (зламаний класифікатор мусить завалити набір)"
mutate() {
  local name="$1" sed_expr="$2" copy="$TMP/mutant.sh"
  sed "$sed_expr" "$SCRIPT_REAL" >"$copy"
  chmod +x "$copy"
  if cmp -s "$copy" "$SCRIPT_REAL"; then
    echo "  ✗ мутація «$name» нічого не змінила — вираз більше не влучає у код"
    suite_fail=1
    return
  fi
  if run_suite "$copy" >"$TMP/mutant.log" 2>&1; then
    echo "  ✗ мутація «$name» пройшла незамічено — гілка не перевіряється"
    sed 's/^/      /' "$TMP/mutant.log"
    suite_fail=1
  else
    echo "  ✓ мутація «$name» впіймана"
  fi
}

mutate "впізнавач soft-denying" 's/soft-denying/ЦЕ-НІКОЛИ-НЕ-ЗБІГАЄТЬСЯ/g'
mutate "впізнавач логіна" 's/accounts\\.google\\.com|//g; s/sign in/ЦЕ-НІКОЛИ-НЕ-ЗБІГАЄТЬСЯ/g'
mutate "впізнавач 401" 's/unauthorized/ЦЕ-НІКОЛИ-НЕ-ЗБІГАЄТЬСЯ/g; s/\\b401\\b/НЕ-ЗБІГ/g'
mutate "перевірка trustedWorkspaces" 's/^WORKSPACE_TRUSTED=.*/WORKSPACE_TRUSTED=yes/'
mutate "звірка nonce" 's/grep -qF -- "\$NONCE"/true #/'

if [[ "$suite_fail" -eq 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
