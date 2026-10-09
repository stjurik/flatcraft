#!/usr/bin/env bash
# dash-collect.test.sh — збір знімка пульту (ADR-042 §10, задача 7): обидва збирачі
# ok; один падає/висне/друкує секрет — лише його розділ error, другий лишається ok;
# час/дата/хеш — не хибні спрацювання; невалідна обгортка — error; відмова писати в
# ~/.flatcraft/ чи в репо; атомарний запис (mv, не пряме перезаписування); реальні
# збирачі хвилі 1 без DASH_COLLECTORS_DIR проходять dash-schema.sh validate; git
# status репо не змінюється.
#
# Мутації в кінці ламають dash-collect.sh по одному правилу — набір мусить
# почервоніти; мутант, що вижив, — привід дописати сценарій, а не довіряти
# зеленому прогону без мутацій.
#
# Запуск: tools/scripts/dash-collect.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${DASH_COLLECT_UNDER_TEST:-$HERE/dash-collect.sh}"
DASHBOARD_DIR="$HERE/../dashboard"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
  [[ -z "${DASH_COLLECT_UNDER_TEST:-}" ]] || exit 1
}

NOW=2026-10-08T12:00:00Z

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# Ізоляція від реальної машини: дефолтний OUT і ~/.flatcraft/ — лише тут, у T.
HOME_T="$T/home"
mkdir -p "$HOME_T"

# mk <dir> <t5-тіло> <trend-тіло> — кладе два заглушкові збирачі в <dir>.
mk() {
  local dir="$1" t5_body="$2" trend_body="$3"
  mkdir -p "$dir"
  { echo '#!/usr/bin/env bash'; printf '%s\n' "$t5_body"; } >"$dir/dash-t5.sh"
  { echo '#!/usr/bin/env bash'; printf '%s\n' "$trend_body"; } >"$dir/dash-trend.sh"
  chmod +x "$dir/dash-t5.sh" "$dir/dash-trend.sh"
}

ENV_T5_OK='echo "{\"schema_version\":1,\"section\":\"t5\",\"title\":\"Трек T5\",\"source\":\"s\",\"collected_at\":\"2026-10-08T12:00:00Z\",\"interval_s\":3600,\"status\":\"ok\",\"origin\":\"measured\",\"data\":{\"n\":1}}"'
ENV_TREND_OK='echo "{\"schema_version\":1,\"section\":\"trend\",\"title\":\"Продукт і процес\",\"source\":\"s\",\"collected_at\":\"2026-10-08T12:00:00Z\",\"interval_s\":3600,\"status\":\"ok\",\"origin\":\"measured\",\"data\":{\"n\":2}}"'

# run <збирачі-dir> <out-dir> [ДОДАТКОВІ_ENV=...] -- друкує stdout+stderr скрипта,
# встановлює $rc. Зовнішній timeout 20 — запобіжник: мутант без внутрішнього
# тайм-ауту (М9 нижче) не має права повісити весь тестовий прогін.
run() {
  local coll="$1" out="$2"
  shift 2
  out_combined="$(env HOME="$HOME_T" DASH_COLLECTORS_DIR="$coll" "$@" timeout 20 bash "$SCRIPT" --out "$out" --now "$NOW" 2>&1)"
  rc=$?
}

sec() { jq -c --arg s "$2" '.sections[] | select(.section == $s)' "$1/snapshot.json" 2>/dev/null; }

# ─── 1. обидва збирачі ok ───────────────────────────────────────────────────
C="$T/c1"; O="$T/o1"
mk "$C" "$ENV_T5_OK" "$ENV_TREND_OK"
run "$C" "$O"
if [[ $rc -eq 0 ]] && jq -e '.sections | length == 2 and all(.status == "ok")' "$O/snapshot.json" >/dev/null 2>&1 &&
  [[ -f "$O/snapshot.js" && -f "$O/index.html" && -f "$O/render.js" ]]; then
  ok "обидва збирачі ok — 2 розділи status ok, усі 4 файли записано"
else
  bad "обидва ok — неочікуваний результат (rc=$rc): $out_combined"
fi

# ─── 2. один падає (exit 1, без секретів) — лише його розділ error ─────────
C="$T/c2"; O="$T/o2"
mk "$C" "$ENV_T5_OK" 'echo звичайна помилка >&2; exit 1'
run "$C" "$O"
if [[ $rc -eq 0 ]] && [[ "$(sec "$O" t5 | jq -r .status)" == ok ]] &&
  [[ "$(sec "$O" trend | jq -r .status)" == error ]] &&
  [[ "$(sec "$O" trend | jq -r '.data.error // ""')" == *"код"* ]]; then
  ok "один падає — його розділ error з кодом, інший лишається ok"
else
  bad "один падає — неочікуваний результат (rc=$rc): $out_combined; $(cat "$O/snapshot.json" 2>/dev/null)"
fi

# ─── 3. один висне довше timeout — лише його розділ error ──────────────────
C="$T/c3"; O="$T/o3"
mk "$C" "$ENV_T5_OK" 'sleep 30'
run "$C" "$O" DASH_COLLECT_TIMEOUT_S=0.3
if [[ $rc -eq 0 ]] && [[ "$(sec "$O" t5 | jq -r .status)" == ok ]] &&
  [[ "$(sec "$O" trend | jq -r .status)" == error ]] &&
  [[ "$(sec "$O" trend | jq -r '.data.error // ""')" == *"тайм-аут"* ]]; then
  ok "один висне — його розділ error з «тайм-аут», інший ok"
else
  bad "один висне — неочікуваний результат (rc=$rc): $out_combined"
fi

# ─── 4–7. секрети: IPv4, IPv6 (документаційні RFC 5737 / RFC 3849), токени,
#          рядок з DASH_LEAK_FILE — розділ error, значення ніде не друкується ──
assert_redacted() { # assert_redacted <назва> <out-dir> <очікуваний-тип-підрядок> <секрет>
  local name="$1" out="$2" type_needle="$3" secret="$4" st reason
  st="$(sec "$out" trend | jq -r .status)"
  reason="$(sec "$out" trend | jq -r '.data.error // ""')"
  if [[ "$st" != error || "$reason" != *"$type_needle"* ]]; then
    bad "$name — очікував error з «$type_needle», отримав status=$st reason=«$reason»"
    return
  fi
  if grep -rqF -- "$secret" "$out" 2>/dev/null; then
    bad "$name — секрет знайдено у $out"
    return
  fi
  if grep -qF -- "$secret" <<<"$out_combined"; then
    bad "$name — секрет знайдено у виводі скрипта"
    return
  fi
  ok "$name — error «$type_needle», секрет ніде не з'явився"
}

C="$T/c4"; O="$T/o4"
mk "$C" "$ENV_T5_OK" 'echo "витік 192.0.2.77 у логах"'
run "$C" "$O"
assert_redacted "IPv4 (документаційний 192.0.2.0/24)" "$O" IPv4 192.0.2.77

C="$T/c5"; O="$T/o5"
mk "$C" "$ENV_T5_OK" 'echo "витік 2001:db8::1 у логах"'
run "$C" "$O"
assert_redacted "IPv6 (документаційний 2001:db8::/32)" "$O" IPv6 2001:db8::1

while IFS='|' read -r label secret; do
  C="$T/c-tok-$label"; O="$T/o-tok-$label"
  mk "$C" "$ENV_T5_OK" "echo 'витік $secret у логах'"
  run "$C" "$O"
  assert_redacted "шаблон токена: $label" "$O" "вирізано" "$secret"
done <<'EOF'
ghp|ghp_FAKEFAKEFAKEFAKEFAKE1234567890
github_pat|github_pat_FAKEFAKEFAKEFAKEFAKE
sk-ant|sk-ant-FAKE1234567890abcdef
age|AGE-SECRET-KEY-1QYQSZQGPQYQSZQ
privkey|-----BEGIN RSA PRIVATE KEY-----
EOF

LEAK_FILE="$T/leak-origin-host"
printf '%s\n' "server.privatecorp.internal-fake" >"$LEAK_FILE"
C="$T/c7"; O="$T/o7"
mk "$C" "$ENV_T5_OK" 'echo "хост: server.privatecorp.internal-fake у журналі"'
run "$C" "$O" DASH_LEAK_FILE="$LEAK_FILE"
assert_redacted "рядок з DASH_LEAK_FILE" "$O" "вирізано" "server.privatecorp.internal-fake"
if grep -rqF -- "server.privatecorp.internal-fake" "$O" 2>/dev/null; then
  bad "DASH_LEAK_FILE — вміст файла все одно потрапив у $O"
else
  ok "DASH_LEAK_FILE — вміст файла ніде не потрапив у знімок"
fi

# ─── 8. час, ISO-дата й хеш коміту — НЕ хибні спрацювання ──────────────────
C="$T/c8"; O="$T/o8"
mk "$C" "$ENV_T5_OK" 'echo "{\"schema_version\":1,\"section\":\"trend\",\"title\":\"T\",\"source\":\"s\",\"collected_at\":\"2026-10-08T12:00:00Z\",\"interval_s\":3600,\"status\":\"ok\",\"origin\":\"measured\",\"data\":{\"time\":\"14:05:12\",\"date\":\"2026-10-08T12:00:00Z\",\"sha\":\"e1fd6d5abc1234\"}}"'
run "$C" "$O"
if [[ "$(sec "$O" trend | jq -r .status)" == ok ]] &&
  [[ "$(sec "$O" trend | jq -r .data.time)" == "14:05:12" ]]; then
  ok "час 14:05:12, ISO-дата і хеш коміту — не вирізано, status ok"
else
  bad "час/дата/хеш хибно вирізано: $(sec "$O" trend)"
fi

# ─── 9. невалідна обгортка (бракує поля) — error, а не пропуск як є ────────
C="$T/c9"; O="$T/o9"
mk "$C" "$ENV_T5_OK" 'echo "{\"schema_version\":1,\"section\":\"trend\",\"title\":\"T\",\"source\":\"s\",\"collected_at\":\"2026-10-08T12:00:00Z\",\"interval_s\":3600,\"status\":\"ok\",\"data\":{}}"'
run "$C" "$O"
if [[ "$(sec "$O" trend | jq -r .status)" == error ]] &&
  [[ "$(sec "$O" trend | jq -r .data.error)" == *"невалідна обгортка"* ]]; then
  ok "невалідна обгортка (бракує origin) — status error з поясненням"
else
  bad "невалідна обгортка — очікував error: $(sec "$O" trend)"
fi

# ─── 10. --out усередині тимчасової «~/.flatcraft» — відмова ───────────────
C="$T/c10"
mk "$C" "$ENV_T5_OK" "$ENV_TREND_OK"
mkdir -p "$HOME_T/.flatcraft/secrets"
run "$C" "$HOME_T/.flatcraft/secrets/out"
if [[ $rc -eq 2 ]] && [[ "$out_combined" == *"flatcraft"* ]]; then
  ok "--out усередині ~/.flatcraft/ — відмова, exit 2"
else
  bad "--out усередині ~/.flatcraft/ — очікував exit 2, отримав $rc: $out_combined"
fi
run "$C" "$HOME_T/.flatcraft"
[[ $rc -eq 2 ]] && ok "--out рівно ~/.flatcraft/ (без підтеки) — теж відмова" ||
  bad "--out рівно ~/.flatcraft/ — очікував exit 2, отримав $rc: $out_combined"

# ─── 11. --out усередині репозиторію — відмова ─────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT")" && pwd)"
REPO_LIKE_TARGET="$SCRIPT_DIR/.."
run "$C" "$REPO_LIKE_TARGET/tmp-dash-collect-test-$$"
if [[ $rc -eq 2 ]] && [[ "$out_combined" == *"репозитор"* ]]; then
  ok "--out усередині репозиторію — відмова, exit 2"
else
  bad "--out усередині репозиторію — очікував exit 2, отримав $rc: $out_combined"
fi

# ─── 12. атомарний запис: temp-файл поруч, потім mv — не пряме записування ─
BIN="$T/bin"
mkdir -p "$BIN"
MVLOG="$T/mvlog"
: >"$MVLOG"
cat >"$BIN/mv" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$MVLOG"
exec /bin/mv "\$@"
EOF
chmod +x "$BIN/mv"
C="$T/c12"; O="$T/o12"
mk "$C" "$ENV_T5_OK" "$ENV_TREND_OK"
out_combined="$(env HOME="$HOME_T" DASH_COLLECTORS_DIR="$C" PATH="$BIN:$PATH" timeout 20 bash "$SCRIPT" --out "$O" --now "$NOW" 2>&1)"
rc=$?
mvlog_content="$(<"$MVLOG")"
if [[ $rc -eq 0 ]] &&
  grep -q "snapshot.json$" <<<"$mvlog_content" && grep -q "snapshot.js$" <<<"$mvlog_content" &&
  grep -q "index.html$" <<<"$mvlog_content" && grep -q "render.js$" <<<"$mvlog_content" &&
  ! grep -qE 'snapshot\.json .*snapshot\.json$' <<<"$mvlog_content"; then
  ok "запис атомарний — кожен файл через mv з окремого тимчасового джерела"
else
  bad "атомарний запис — mv не викликано як очікувалось: $mvlog_content"
fi

# ─── 13–14. лише top-level (не для мутантів): реальні збирачі й git status ──
if [[ -z "${DASH_COLLECT_UNDER_TEST:-}" ]]; then
  REPO_ROOT="$(cd "$HERE/../.." && pwd)"
  if git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    BEFORE="$(git -C "$REPO_ROOT" status --porcelain)"
    O="$T/o-real"
    out_combined="$(env HOME="$HOME_T" timeout 20 bash "$SCRIPT" --out "$O" --now "$NOW" 2>&1)"
    rc=$?
    AFTER="$(git -C "$REPO_ROOT" status --porcelain)"
    if [[ $rc -eq 0 ]] && [[ "$BEFORE" == "$AFTER" ]]; then
      ok "git status репо не змінюється після збору справжніми збирачами"
    else
      bad "git status змінився після збору (rc=$rc): до=«$BEFORE» після=«$AFTER»; $out_combined"
    fi
    for s in t5 trend; do
      env_file="$T/real-$s.json"
      sec "$O" "$s" >"$env_file"
      vout="$(bash "$HERE/dash-schema.sh" validate "$env_file" 2>&1)"
      status="$(jq -r .status <"$env_file" 2>/dev/null)"
      if [[ "$vout" == ok && "$status" != error ]]; then
        ok "реальний збирач «$s» — обгортка проходить validate, status не error"
      else
        bad "реальний збирач «$s» — validate=«$vout» status=«$status»: $(cat "$env_file")"
      fi
    done
  else
    echo "пропуск сценарію 13–14: «$REPO_ROOT» не git-репозиторій" >&2
  fi
fi

# ─── 15. базові відмови CLI ─────────────────────────────────────────────────
out_combined="$(env HOME="$HOME_T" timeout 20 bash "$SCRIPT" --дивний 2>&1)"
rc=$?
[[ $rc -eq 2 ]] && ok "невідомий прапорець — exit 2" || bad "невідомий прапорець — очікував exit 2, отримав $rc"

out_combined="$(env HOME="$HOME_T" timeout 20 bash "$SCRIPT" --out 2>&1)"
rc=$?
[[ $rc -eq 2 ]] && ok "--out без значення — exit 2" || bad "--out без значення — очікував exit 2, отримав $rc"

out_combined="$(env HOME="$HOME_T" timeout 20 bash "$SCRIPT" --now "не-дата" --out "$T/o-bad-now" 2>&1)"
rc=$?
[[ $rc -eq 2 ]] && ok "--now у неправильному форматі — exit 2" || bad "--now у неправильному форматі — очікував exit 2, отримав $rc"

# ─── Мутації: кожне правило тримається тестом ───────────────────────────────
if [[ -z "${DASH_COLLECT_UNDER_TEST:-}" && $fail -eq 0 ]]; then
  M="$(mktemp -d)"
  trap 'rm -rf "$M" "$T"' EXIT
  src="$(<"$SCRIPT")"
  n=0
  mutate() { # mutate <назва> <було> <стало> — «було» має стояти в скрипті рівно раз
    local name="$1" from="$2" to="$3" d="$M/$((++n))" rest
    rest="${src#*"$from"}"
    if [[ "$rest" == "$src" || "$rest" == *"$from"* ]]; then
      bad "мутант «$name»: текст не знайдено рівно один раз — мутація застаріла"
      return
    fi
    mkdir -p "$d/scripts" "$d/dashboard"
    cp "$HERE/dash-schema.sh" "$d/scripts/dash-schema.sh"
    cp "$DASHBOARD_DIR/index.html" "$d/dashboard/index.html"
    cp "$DASHBOARD_DIR/render.js" "$d/dashboard/render.js"
    cp "$DASHBOARD_DIR/snapshot.schema.json" "$d/dashboard/snapshot.schema.json"
    printf '%s\n' "${src/"$from"/"$to"}" >"$d/scripts/dash-collect.sh"
    if DASH_COLLECT_UNDER_TEST="$d/scripts/dash-collect.sh" bash "$HERE/$(basename "$0")" >"$d/out" 2>&1; then
      bad "мутант ВИЖИВ: $name"
    else
      ok "мутанта вбито: $name"
    fi
  }

  mutate "IPv6-шаблон вимкнено" \
    'IPV6_RE="$IPV6_RE|:((:[0-9A-Fa-f]{1,4}){1,7}|:)"' \
    'IPV6_RE="no-match-at-all-xyz"'
  mutate "IPv4-шаблон вимкнено" \
    'IPV4_RE="\\b${IPV4_OCTET}(\\.${IPV4_OCTET}){3}\\b"' \
    'IPV4_RE="no-match-at-all-xyz"'
  mutate "DASH_LEAK_FILE не читається" \
    'if [[ -r "$LEAK_FILE" && -s "$LEAK_FILE" ]]; then' \
    'if false; then'
  mutate "збій одного збирача зупиняє весь збір" \
    'data="$(jq -nc --arg reason "$reason" '"'"'{error: $reason}'"'"')"' \
    'data="$(jq -nc --arg reason "$reason" '"'"'{error: $reason}'"'"')"; exit 1'
  mutate "запис без тимчасового файла (atomic_write напряму)" \
    'tmp="$(mktemp "$(dirname -- "$dest")/.dash-collect.XXXXXX")"
  printf '"'"'%s'"'"' "$content" >"$tmp"
  mv -f -- "$tmp" "$dest"' \
    'printf '"'"'%s'"'"' "$content" >"$dest"'
  mutate "копіювання без тимчасового файла (atomic_copy напряму)" \
    'tmp="$(mktemp "$(dirname -- "$dest")/.dash-collect.XXXXXX")"
  cp -f -- "$src" "$tmp"
  mv -f -- "$tmp" "$dest"' \
    'cp -f -- "$src" "$dest"'
  mutate "валідація обгортки пропускається" \
    'if [[ "$vout" != ok ]]; then' \
    'if false; then'
  mutate "тайм-аут на збирач вимкнено" \
    'timeout -k 2 "$TIMEOUT_S" bash "$path" --now "$NOW" >"$out_f" 2>"$err_f"' \
    'bash "$path" --now "$NOW" >"$out_f" 2>"$err_f"'
  mutate "відмова для ~/.flatcraft/ вимкнена" \
    '    echo "відмова: --out усередині ~/.flatcraft/ — там секрети оркестратора (ADR-042 §5)" >&2
    exit 2' \
    '    true'
  mutate "відмова для шляху в репо вимкнена" \
    '    echo "відмова: --out усередині репозиторію (ADR-042 §5)" >&2
    exit 2' \
    '    true'

  rm -rf "$M"
fi

if [[ $fail -eq 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
