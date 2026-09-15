#!/usr/bin/env bash
# check-agy-headless.sh — одна команда, що відповідає на питання D.4:
# чи може НЕПИЛЬНОВАНИЙ агент викликати Gemini на цій машині.
#
# ЧОМУ ЦЕ ІСНУЄ. ADR-039 §5 будує на `agy` другий квотний пул і read-only
# резерв на час вичерпаної Claude-квоти, і сам фіксує: доки D.4 не закритий,
# Gemini-пулу на A8 немає. `docs/19` §D.4 пропонував три розпливчасті варіанти
# «спробуйте по черзі» — тобто ритуал. Ритуал, який ніхто не прогнав, і є той
# самий клас «декларація замість механізму», проти якого написаний `docs/16` §1.
#
# ЩО ПЕРЕВІРЯЄТЬСЯ — увесь ланцюг, потрібний оркестратору, а не «чи щось
# надрукувалось»: тека довірена → `agy` запускається → читає файл (`read_file`)
# → пише файл (`write_file`) → написане містить саме те, що просили → нічого
# стороннього не зачепив. Розрив у будь-якій ланці робить Gemini-пул непридатним.
#
# Три відомі капкани (`agy-orchestration-recommendations.md` §3-4) — враховані,
# не перевідкриваються:
#   1. `agy -p` НЕ читає stdin → контекст передається ФАЙЛОМ, з проханням
#      прочитати його через `read_file`;
#   2. будь-який bash-виклик поза allow-list'ом ТИХО падає
#      (`soft-denying tool confirmation "Bash"`) і `agy` завершується без
#      результату — це легко сплутати з проблемою логіна, тому bash заборонений
#      у самому промпті, а лог перевіряється на цю сигнатуру ОКРЕМОЮ гілкою;
#   3. `write_file(*)` ширший за задум → `git status` звіряється до і після
#      через `check-agy-scope.sh` (baseline'ом, бо дерево буває брудним).
#
# Вердикти (exit-код = гілка таблиці `docs/19` §D.4):
#   0 — ✅ PASS: увесь ланцюг працює, Gemini-пул на A8 можливий;
#   1 — ❌ інструменти заблоковані (allow-list, НЕ логін);
#   2 — ⚠️  потрібен браузер → варіанти 2-3 `docs/19` §D.4;
#   3 — ❌ креденшали недійсні;
#   4 — ❌ таймаут;
#   5 — ❌ відповів, але завдання не виконав;
#   6 — ⚠️  scope-creep: писав поза `docs/promts/inputs/**` (Master Run 8);
#   7 — ЗНЯТО 2026-09-15, код більше не повертається (нумерація 8 збережена
#       свідомо: на неї посилаються `docs/19` §D.4 і цей набір тестів).
#       Був: «робоча тека поза `trustedWorkspaces` — відмова ДО витрати виклику».
#       Чому знято: блокування спрацьовувало ДО виміру, а скрипт, який
#       відмовляється міряти, не може нічого довести. Додатково воно було хибним
#       за будь-якої гіпотези — точний збіг відхиляв підтеки довірених коренів.
#       Тека поза списком тепер лише позначається у виводі;
#   8 — помилка виклику (немає `agy`, немає `timeout`, тека не git-репозиторій).
#
# Використання:
#   tools/scripts/check-agy-headless.sh [--timeout СЕК] [--keep]
#
# Про `trustedWorkspaces` (`~/.gemini/antigravity-cli/settings.json`): скрипт
# звіряє, чи тека у списку, але через це НЕ відмовляється працювати. Вимір
# 2026-09-15 показав, що в режимі `-p` список не гейтить ні виклик моделі, ні
# `read_file`/`write_file`; вимір 2026-09-14 показав протилежне (браузерний
# OAuth з worktree). Суперечність не закрита — обидві точки в `docs/19` §D.4.
# Поки вона відкрита, правильна поведінка — МІРЯТИ і показати примітку, а не
# вгадувати наперед: якщо браузерний OAuth таки з'явиться, вивід зонда
# покаже і його, і те, що тека була поза списком.
set -uo pipefail

TIMEOUT=240
KEEP=no
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --keep) KEEP=yes; shift ;;
    -h|--help) sed -n '2,50p' "$0"; exit 0 ;;
    *) echo "::error::невідомий аргумент «$1»" >&2; exit 8 ;;
  esac
done

die_misuse() {
  echo "::error::$1" >&2
  exit 8
}

command -v agy >/dev/null 2>&1 || die_misuse "у PATH немає \`agy\` — нічого перевіряти"
command -v timeout >/dev/null 2>&1 || die_misuse "у PATH немає \`timeout\` (coreutils)"

WORKSPACE="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die_misuse "поточна тека не є git-репозиторієм"

SETTINGS="$HOME/.gemini/antigravity-cli/settings.json"
SCOPE_GUARD="$(cd "$(dirname "$0")" && pwd)/check-agy-scope.sh"

# ── Гілка 7: тека мусить бути довіреною ────────────────────────────────────
# Перевіряємо ПЕРЕД викликом: недовірена тека дає відмову, яку легко прийняти
# за збій логіна, а виклик при цьому вже витрачений.
WORKSPACE_TRUSTED="$(
  python3 - "$SETTINGS" "$WORKSPACE" <<'PY' 2>/dev/null || echo unknown
import json, os, sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        trusted = json.load(fh).get("trustedWorkspaces", [])
except (OSError, ValueError):
    print("unknown")
    sys.exit(0)
target = os.path.realpath(sys.argv[2])
print("yes" if any(os.path.realpath(p) == target for p in trusted) else "no")
PY
)"

# НЕ блокуємо: див. шапку, вердикт 7 знято 2026-09-15. Примітка лишається, бо
# вона — половина діагнозу, якщо `agy` таки попросить браузер: тоді у виводі
# видно і запит логіна, і те, що тека була поза списком.
if [[ "$WORKSPACE_TRUSTED" != yes ]]; then
  echo "── Примітка: тека поза trustedWorkspaces — зонд міряє далі"
  echo "   тека:   $WORKSPACE"
  echo "   список: $SETTINGS"
  if [[ "$WORKSPACE_TRUSTED" == unknown ]]; then
    echo "   (файл налаштувань не прочитався — перевірте, чи \`agy\` тут налаштований)"
  fi
  echo "   Вимір 2026-09-15: у режимі \`-p\` список не гейтив ні виклик моделі,"
  echo "   ні read_file/write_file. Вимір 2026-09-14 давав браузерний OAuth."
  echo "   Суперечність відкрита (docs/19 §D.4). Якщо нижче буде запит логіна —"
  echo "   спробуйте: tools/scripts/trust-worktree.sh add $WORKSPACE"
  echo
fi

# ── Підготовка зонда ───────────────────────────────────────────────────────
INPUTS_DIR="$WORKSPACE/docs/promts/inputs"
[[ -d "$INPUTS_DIR" ]] || die_misuse "немає теки $INPUTS_DIR"
IN_FILE="$INPUTS_DIR/_agy-probe-input.md"
OUT_FILE="$INPUTS_DIR/_agy-probe-output.md"
LOG_FILE="$(mktemp -t agy-probe-XXXXXX.log)"
RUN_OUT="$(mktemp -t agy-probe-stdout-XXXXXX.txt)"
NONCE="AGY-PROBE-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"

# Baseline знімаємо ДО створення файлів зонда: далі порівнюється різниця, а не
# абсолютний список — дерево під час прогону майже завжди брудне.
BASELINE="$(mktemp -t agy-probe-baseline-XXXXXX.txt)"
git -C "$WORKSPACE" status --porcelain >"$BASELINE"

cleanup() {
  if [[ "$KEEP" == yes ]]; then
    echo "   (--keep: файли зонда лишено — $IN_FILE, $OUT_FILE)"
  else
    rm -f "$IN_FILE" "$OUT_FILE"
  fi
  rm -f "$BASELINE"
}
trap cleanup EXIT

cat >"$IN_FILE" <<EOF
# Транзитний вхід зонда D.4 — не редагувати, не комітити

NONCE=$NONCE
EOF

PROMPT="НЕ використовуй жодних command/bash/terminal інструментів — лише read_file і write_file.
1. Прочитай через read_file файл $IN_FILE
2. Знайди в ньому рядок, що починається з NONCE=
3. Через write_file запиши у файл $OUT_FILE РІВНО одне значення — те, що стоїть після NONCE=
Нічого іншого не роби і жодних інших файлів не змінюй."

echo "── зонд D.4: $WORKSPACE (таймаут ${TIMEOUT}с, лог $LOG_FILE)"
agy_exit=0
timeout "$TIMEOUT" agy --log-file "$LOG_FILE" -p "$PROMPT" >"$RUN_OUT" 2>&1 || agy_exit=$?

# Усе, що побачив оркестратор — і stdout, і лог: сигнатури трапляються в обох.
EVIDENCE="$(cat "$RUN_OUT" "$LOG_FILE" 2>/dev/null)"

# ── Класифікація ───────────────────────────────────────────────────────────
# Порядок не випадковий: спершу те, що має однозначну сигнатуру (заблоковані
# інструменти, логін, креденшали, таймаут), і лише потім — висновки з вмісту
# файлу. Так «тихе падіння» tool-confirmation не діагностується як «логін».
verdict_code=""
verdict_text=""
set_verdict() { verdict_code="$1"; verdict_text="$2"; }

if grep -qi -- "soft-denying" <<<"$EVIDENCE"; then
  set_verdict 1 "❌ інструменти заблоковані allow-list'ом (НЕ логін) — agy впав тихо"
elif grep -qiE -- "accounts\.google\.com|sign in|log in to continue|please authenticate|authorization required" <<<"$EVIDENCE"; then
  set_verdict 2 "⚠️  потрібен браузер: agy просить інтерактивний логін"
elif grep -qiE -- "\b401\b|unauthorized|invalid bearer|api key" <<<"$EVIDENCE"; then
  set_verdict 3 "❌ креденшали недійсні"
elif [[ "$agy_exit" -eq 124 ]]; then
  set_verdict 4 "❌ таймаут ${TIMEOUT}с — agy не завершив роботу"
elif [[ -s "$OUT_FILE" ]] && grep -qF -- "$NONCE" "$OUT_FILE"; then
  set_verdict 0 "✅ PASS: read_file + write_file працюють, nonce повернувся дослівно"
elif [[ -f "$OUT_FILE" ]]; then
  set_verdict 5 "❌ agy відповів, але nonce у вихідному файлі немає — завдання не виконано"
else
  set_verdict 5 "❌ вихідного файлу немає — agy не виконав write_file"
fi

# ── Гілка 6: scope-creep перевіряється ЗАВЖДИ ──────────────────────────────
# Навіть на PASS: самовільний запис — інцидент, який вимагає рішення людини,
# тому він перебиває код вердикту, але НЕ приховує його (обидва факти у звіті).
scope_out=""
scope_exit=0
if [[ -x "$SCOPE_GUARD" ]]; then
  scope_out="$(git -C "$WORKSPACE" status --porcelain | "$SCOPE_GUARD" "$BASELINE" 2>&1)" || scope_exit=$?
fi

echo
echo "── Вердикт D.4: $verdict_text"
echo "   exit agy: $agy_exit | nonce: $NONCE"
if [[ -s "$RUN_OUT" ]]; then
  echo "   ── дослівний вивід agy ──"
  sed 's/^/   /' "$RUN_OUT"
fi
if [[ "$verdict_code" -eq 0 ]]; then
  echo "   ── вміст вихідного файлу ──"
  sed 's/^/   /' "$OUT_FILE"
fi

if [[ "$scope_exit" -ne 0 ]]; then
  echo
  echo "── ⚠️  scope-creep: agy писав поза docs/promts/inputs/ (повторення Master Run 8)"
  sed 's/^/   /' <<<"$scope_out"
  echo
  echo "Вердикт ланцюга при цьому: $verdict_text"
  exit 6
fi

echo "   scope: OK (нових змін поза docs/promts/inputs/ немає)"
exit "$verdict_code"
