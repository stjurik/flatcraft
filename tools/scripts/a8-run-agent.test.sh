#!/usr/bin/env bash
# a8-run-agent.test.sh — доказ, що креденшали двох виконавців не перетинаються
# (PR-B #262, orchestrator-autonomy.md §8): у контейнері agy немає токена Claude,
# у контейнері Claude немає креденшалів Google.
#
# ЧОМУ ОКРЕМИЙ ТЕСТ. a8-tick.test.sh підміняє обгортку заглушкою: справжній шаблон
# a8-run-agent там не виконується жодного разу (шапка інваріанта 6 у
# check-ansible-a8.sh). А саме обгортка вирішує, що змонтувати і що передати в
# контейнер. Тут виконується СПРАВЖНІЙ шаблон, відрендерений підстановками, а
# підмінено лише `docker` (друкує свої аргументи) і `a8-guard`.
#
# Чого НЕ доводить: що docker справді монтує так, як написано в аргументах, і
# що agy в контейнері бачить свою теку. Це живий вимір V23 у verify.yml.
#
# Мутації в кінці: ламаємо шаблон по одному місцю — набір мусить почервоніти.
#
# Запуск: tools/scripts/a8-run-agent.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL_REPO="$HERE/../../infra/ansible/roles/a8/templates/a8-run-agent.sh.j2"
TPL="${A8_RUNNER_UNDER_TEST:-$TPL_REPO}"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
fail=0
say() { [[ -z "${QUIET:-}" ]] && echo "$@"; return 0; }
ok() { say "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
}

CH="/home/agent/container-home"
AGYBIN="/usr/local/bin/agy"
mkdir -p "$ROOT/etc" "$ROOT/bin" "$ROOT/repo" "$ROOT/wt" "$ROOT/agy-home"
: >"$ROOT/etc/a8.env"
# a8-guard: код зі змінної GUARD_RC (за замовчуванням 0 — запобіжники мовчать).
cat >"$ROOT/bin/a8-guard" <<'STUB'
#!/usr/bin/env bash
exit "${GUARD_RC:-0}"
STUB
# docker: кожен аргумент — окремим рядком, плюс маркер виклику.
cat >"$ROOT/bin/docker" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$ROOT/docker-args"
STUB
chmod +x "$ROOT/bin/a8-guard" "$ROOT/bin/docker"

# Рендер — лише підстановки, яких вистачає цьому шаблону. Будь-яка невідрендерена
# {{ … }} — помилка тесту, а не тиха порожнеча.
sed -e "s|{{ ansible_managed }}|test render|" \
  -e "s|{{ a8_config_dir }}|$ROOT/etc|g" \
  -e "s|{{ a8_repo_dir }}|$ROOT/repo|g" \
  -e "s/{{ a8_ro_paths | join(' ') }}/infra\/ansible .github/g" \
  -e "s|{{ a8_container_uid }}|1002|g" -e "s|{{ a8_container_gid }}|1002|g" \
  -e "s|{{ a8_container_home }}|$CH|g" \
  -e "s|{{ a8_python_version }}|3.12|g" \
  -e "s|{{ a8_git_author_name }}|a|g" -e "s|{{ a8_git_author_email }}|a@a|g" \
  -e "s|{{ a8_container_image }}|hart-agent:test|g" \
  -e "s|{{ a8_agy_bin }}|$AGYBIN|g" \
  -e "s/{{ a8_agy_extra_ro_paths | join(' ') }}/\/opt\/agy-lib/g" \
  -e "s|/usr/local/bin/a8-guard|$ROOT/bin/a8-guard|g" \
  "$TPL" >"$ROOT/a8-run-agent"
if grep -q '{{' "$ROOT/a8-run-agent"; then
  bad "у шаблоні лишились невідрендерені місця: $(grep -o '{{[^}]*}}' "$ROOT/a8-run-agent" | sort -u | tr '\n' ' ')"
fi

# run [ЗМІННА=значення…] — обгортка з чистим середовищем, крім заданого.
# Повертає код обгортки; аргументи docker — у $ROOT/docker-args (немає файла —
# docker не викликано).
run() {
  rm -f "$ROOT/docker-args"
  env -i PATH="$ROOT/bin:/usr/bin:/bin" "$@" bash "$ROOT/a8-run-agent" "$ROOT/wt" agy -p x >"$ROOT/out" 2>&1
}
has_arg() { grep -qxF -- "$1" "$ROOT/docker-args" 2>/dev/null; }
mentions() { grep -qF -- "$1" "$ROOT/docker-args" 2>/dev/null; }

# 1. Claude з токеном — токен передається ІМЕНЕМ, теки agy і самого agy немає.
rc=0
run A8_EXECUTOR=claude CLAUDE_CODE_OAUTH_TOKEN=tok || rc=$?
if ((rc == 0)) && has_arg CLAUDE_CODE_OAUTH_TOKEN && ! mentions tok; then
  ok "claude: токен передано іменем (-e CLAUDE_CODE_OAUTH_TOKEN), значення в аргументах немає"
else
  bad "claude: токен (rc=$rc): $(tr '\n' ' ' <"$ROOT/docker-args" 2>/dev/null)"
fi
if mentions .gemini || mentions "$AGYBIN" || mentions /opt/agy-lib; then
  bad "claude: у контейнері є тека agy або сам agy: $(tr '\n' ' ' <"$ROOT/docker-args")"
else
  ok "claude: ні теки налаштувань agy, ні agy, ні його бібліотек у контейнері"
fi

# 2. Без A8_EXECUTOR — це claude, як до смуги.
rc=0
run CLAUDE_CODE_OAUTH_TOKEN=tok || rc=$?
((rc == 0)) && has_arg CLAUDE_CODE_OAUTH_TOKEN && ! mentions .gemini &&
  ok "без A8_EXECUTOR → claude, як до смуги" || bad "без A8_EXECUTOR (rc=$rc)"

# 3. Claude, а в середовищі випадково є A8_AGY_HOME — креденшали Google однаково
# не монтуються: вирішує виконавець, а не наявність змінної.
rc=0
run A8_EXECUTOR=claude A8_AGY_HOME="$ROOT/agy-home" || rc=$?
((rc == 0)) && ! mentions "$ROOT/agy-home" &&
  ok "claude з A8_AGY_HOME у середовищі — теку agy однаково не змонтовано" ||
  bad "claude змонтував теку agy (rc=$rc): $(tr '\n' ' ' <"$ROOT/docker-args" 2>/dev/null)"

# 4. Gemini — тека agy на $HOME/.gemini, agy лише для читання, токена Claude немає.
rc=0
run A8_EXECUTOR=gemini A8_AGY_HOME="$ROOT/agy-home" || rc=$?
if ((rc == 0)) && has_arg "$ROOT/agy-home:$CH/.gemini" && has_arg "$AGYBIN:/usr/local/bin/agy:ro" &&
  has_arg "/opt/agy-lib:/opt/agy-lib:ro"; then
  ok "gemini: тека agy на \$HOME/.gemini, agy і його бібліотеки — лише читання"
else
  bad "gemini: монтування (rc=$rc): $(tr '\n' ' ' <"$ROOT/docker-args" 2>/dev/null) $(cat "$ROOT/out")"
fi
mentions CLAUDE_CODE_OAUTH_TOKEN && bad "gemini: у контейнер іде CLAUDE_CODE_OAUTH_TOKEN" ||
  ok "gemini: CLAUDE_CODE_OAUTH_TOKEN у контейнер не йде"

# 5. Gemini, а токен Claude у середовищі є → відмова, контейнер не стартує.
rc=0
run A8_EXECUTOR=gemini A8_AGY_HOME="$ROOT/agy-home" CLAUDE_CODE_OAUTH_TOKEN=tok || rc=$?
((rc == 2)) && [[ ! -e "$ROOT/docker-args" ]] && grep -q CLAUDE_CODE_OAUTH_TOKEN "$ROOT/out" &&
  ok "gemini з токеном Claude у середовищі → відмова (2), docker не викликано" ||
  bad "gemini з токеном Claude: rc=$rc, docker $([[ -e "$ROOT/docker-args" ]] && echo викликано || echo ні)"

# 6. Gemini без теки налаштувань → відмова: agy без профілю «виконавець» —
# це agy з профілем, який лежить на хості (рецензент або ширший).
rc=0
run A8_EXECUTOR=gemini || rc=$?
((rc == 2)) && [[ ! -e "$ROOT/docker-args" ]] &&
  ok "gemini без A8_AGY_HOME → відмова (2), docker не викликано" || bad "gemini без A8_AGY_HOME: rc=$rc"
rc=0
run A8_EXECUTOR=gemini A8_AGY_HOME="$ROOT/none" || rc=$?
((rc == 2)) && [[ ! -e "$ROOT/docker-args" ]] &&
  ok "gemini з A8_AGY_HOME на неіснуючу теку → відмова (2)" || bad "gemini з неіснуючою текою: rc=$rc"

# 7. Невідомий виконавець → відмова, а не «мабуть, claude».
rc=0
run A8_EXECUTOR=codex CLAUDE_CODE_OAUTH_TOKEN=tok || rc=$?
((rc == 2)) && [[ ! -e "$ROOT/docker-args" ]] &&
  ok "невідомий виконавець → відмова (2), docker не викликано" || bad "невідомий виконавець: rc=$rc"

# 8. Kill switch в обгортці — як і раніше, код запобіжника, контейнер не стартує.
rc=0
run A8_EXECUTOR=gemini A8_AGY_HOME="$ROOT/agy-home" GUARD_RC=10 || rc=$?
((rc == 10)) && [[ ! -e "$ROOT/docker-args" ]] &&
  ok "STOP → 10 і для gemini, контейнер не стартує" || bad "STOP для gemini: rc=$rc"

if [[ -z "${A8_RUNNER_UNDER_TEST:-}" && "$fail" -ne 0 ]]; then
  echo "✗ мутації НЕ ганялись: базовий набір червоний (на червоному базисі кожен мутант «вбитий»)."
elif [[ -z "${A8_RUNNER_UNDER_TEST:-}" ]]; then
  mutate() { # mutate <назва> <perl-вираз>
    local m="$ROOT/mutant.j2"
    perl -0pe "$2" "$TPL_REPO" >"$m"
    if cmp -s "$m" "$TPL_REPO"; then
      bad "мутація «$1» нічого не змінила — вираз застарів"
      return
    fi
    if QUIET=1 A8_RUNNER_UNDER_TEST="$m" bash "$0" >/dev/null 2>&1; then
      bad "мутація «$1» ВИЖИЛА — набір зелений на зламаній обгортці"
    else
      ok "мутація «$1» убита"
    fi
  }
  # «Передати токен, якщо він є» в гілці gemini — мутант-двійник: токен у
  # середовищі там і так дає відмову. Тому ламаємо інакше — `-e` без умови.
  mutate "gemini передає -e CLAUDE_CODE_OAUTH_TOKEN" \
    's/(    OPT_ARGS\+=\(-v "\$A8_AGY_HOME)/    OPT_ARGS+=(-e CLAUDE_CODE_OAUTH_TOKEN)\n$1/'
  mutate "gemini не відмовляє на токені Claude" \
    's/(    if \[\[ -n "\$\{CLAUDE_CODE_OAUTH_TOKEN:-\}" \]\]; then\n.*?\n)      exit 2\n/$1/s'
  mutate "тека agy монтується і для claude" \
    's/(case "\$\{A8_EXECUTOR:-claude\}" in\n)/[[ -n "\${A8_AGY_HOME:-}" ]] \&\& OPT_ARGS+=(-v "\$A8_AGY_HOME:{{ a8_container_home }}\/.gemini")\n$1/'
  mutate "невідомий виконавець = claude" 's/  claude\)\n/  claude | *)\n/'
  mutate "agy з хоста на запис" 's/:\/usr\/local\/bin\/agy:ro/:\/usr\/local\/bin\/agy/'
  mutate "gemini без перевірки теки налаштувань" 's/ \|\| ! -d "\$A8_AGY_HOME"//; s/-z "\$\{A8_AGY_HOME:-\}" \|\| //'
  mutate "бібліотеки agy на запис" 's/OPT_ARGS\+=\(-v "\$p:\$p:ro"\)/OPT_ARGS+=(-v "\$p:\$p")/'
fi

if ((fail)); then
  echo "FAIL"
  exit 1
fi
say "Усі тести пройдено."
exit 0
