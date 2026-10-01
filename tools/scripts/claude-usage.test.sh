#!/usr/bin/env bash
# claude-usage.test.sh — підрахунок звернень Claude Code на штучних журналах: лише
# assistant з usage, рядки одного id — одне звернення з максимумом токенів, день/сесія/
# модель, середній контекст, --since, і ГОЛОВНЕ — у виводі немає ні тексту повідомлень, ні шляхів.
# Справжні журнали тест не читає. Запуск: tools/scripts/claude-usage.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${CLAUDE_USAGE_UNDER_TEST:-$HERE/claude-usage.sh}"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
  [[ -z "${CLAUDE_USAGE_UNDER_TEST:-}" ]] || exit 1
}
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# a <день> <сесія> <id> <модель> <input> <cache_read> <cache_creation> <output> [текст]
a() {
  printf '{"type":"assistant","timestamp":"%sT10:00:00.000Z","sessionId":"%s","cwd":"/home/secret-путь/repo","message":{"id":"%s","model":"%s","content":[{"type":"text","text":"%s"}],"usage":{"input_tokens":%s,"cache_read_input_tokens":%s,"cache_creation_input_tokens":%s,"output_tokens":%s}}}\n' \
    "$1" "$2" "$3" "$4" "${9:-СЕКРЕТНИЙ-ТЕКСТ}" "$5" "$6" "$7" "$8"
}
J="$T/журнали/-home-secret-путь"
mkdir -p "$J/sess-b/subagents"
{
  a 2026-09-30 aaaaaaaa-1111-2222-3333-444444444444 m1 claude-opus-5-5 10 100 0 5
  # Той самий id — наступний блок тієї ж відповіді: те саме звернення, output більший.
  a 2026-09-30 aaaaaaaa-1111-2222-3333-444444444444 m1 claude-opus-5-5 10 100 0 9
  # І ще один рядок m1 з меншим output: максимум лишається 9 (не «останній рядок»).
  a 2026-09-30 aaaaaaaa-1111-2222-3333-444444444444 m1 claude-opus-5-5 10 100 0 3
  echo ''
  a 2026-09-30 aaaaaaaa-1111-2222-3333-444444444444 m2 claude-opus-5-5 0 300 100 15
  echo '{"type":"user","timestamp":"2026-09-30T10:00:00Z","sessionId":"aaaaaaaa","message":{"content":"СЕКРЕТ-КОРИСТУВАЧА"}}'
  # Не assistant, хоч і з id та usage (напр. запис прогресу субагента) — пропуск.
  a 2026-09-30 aaaaaaaa-1111-2222-3333-444444444444 m7 claude-opus-5-5 5000 0 0 5000 | sed 's/"type":"assistant"/"type":"progress"/'
  # assistant без usage — пропуск
  echo '{"type":"assistant","timestamp":"2026-09-30T10:00:00Z","sessionId":"aaaaaaaa","message":{"id":"m9","model":"claude-opus-5-5"}}'
  echo 'не json {'
  a 2026-09-28 aaaaaaaa-1111-2222-3333-444444444444 m3 claude-opus-5-5 1 1 1 1
  # Мітка часу — не дата, модель — не коротка назва, від'ємні токени: у вивід лише «?» і 0.
  a 2026-09-30 aaaaaaaa-1111-2222-3333-444444444444 m6 СЕКРЕТНА-МОДЕЛЬ -50 3 0 -7 | sed 's/"timestamp":"[^"]*"/"timestamp":"СЕКРЕТ-У-ЧАСІ-xx"/'
  a 2026-09-30 aaaaaaaa-1111-2222-3333-444444444444 m8 tokenXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX 2 0 0 2
  a 2026-09-30 aaaaaaaa-1111-2222-3333-444444444444 m10 claude-opus-5-5 1 0 0 1 | sed 's/"sessionId":"[^"]*",//'
} >"$J/aaaaaaaa.jsonl"
a 2026-10-01 bbbbbbbb-1111-2222-3333-444444444444 m4 claude-sonnet-5-5 20 0 0 7 >"$J/bbbbbbbb.jsonl"
a 2026-10-01 bbbbbbbb-1111-2222-3333-444444444444 m5 claude-haiku-4-5-20251001 4 0 0 1 >"$J/sess-b/subagents/agent-x.jsonl"
echo 'тут теж СЕКРЕТНИЙ-ТЕКСТ' >"$J/notes.txt"
# Файл, який не відкривається (під root читається — тоді сценарій пропускаємо).
a 2026-10-01 cccccccc-1111 m11 claude-opus-5-5 1 0 0 1 >"$J/закритий-secret.jsonl"
chmod 000 "$J/закритий-secret.jsonl"
[[ -r "$J/закритий-secret.jsonl" ]] && closed=0 || closed=1

out="$(bash "$SCRIPT" "$T/журнали" 2>&1)"
rc=$?
check() { # check <назва> <регекс рядка виводу>
  if grep -Eq -- "$2" <<<"$out"; then ok "$1"; else bad "$1 — немає рядка /$2/ у виводі:
$out"; fi
}
[[ $rc == 0 ]] && ok "exit 0" || bad "exit $rc: $out"
# m1 (110, output max(5,9)=9) і m2 (400, 15): 2 звернення, середній контекст 255, output 24.
check "рядки одного id — одне звернення, output — максимум" '^2026-09-30 +aaaaaaaa +claude-opus-5-5 +2 +255 +24$'
check "мітка часу не дата — день «?», модель не коротка — «?», від'ємне — 0" '^\?{4}-\?{2}-\?{2} +aaaaaaaa +\? +1 +3 +0$'
check "задовга модель — «?»" '^2026-09-30 +aaaaaaaa +\? +1 +2 +2$'
check "без сесії — «?»" '^2026-09-30 +\? +claude-opus-5-5 +1 +1 +1$'
check "шапка таблиці" '^день +сесія +модель +звернень +сер\.контекст +output$'
check "РАЗОМ за кожен день" '^2026-09-28 +РАЗОМ +1 +3 +1$'
check "РАЗОМ з кількома рядками дня" '^2026-09-30 +РАЗОМ +4 +128 +27$'
check "інший день — окремий рядок" '^2026-09-28 +aaaaaaaa +claude-opus-5-5 +1 +3 +1$'
check "сесія з двома моделями — по рядку на модель" '^2026-10-01 +bbbbbbbb +claude-sonnet-5-5 +1 +20 +7$'
check "журнал субагента в підтеці — теж рахується" '^2026-10-01 +bbbbbbbb +claude-haiku-4-5-20251001 +1 +4 +1$'
check "РАЗОМ за день" '^2026-10-01 +РАЗОМ +2 +12 +8$'
check "нерозібраний рядок порахований, порожній — ні" '^нерозібраних рядків: 1$'
check "файл, що не відкрився, порахований" "^файлів, що не відкрились: $closed\$"
for leak in СЕКРЕТНИЙ СЕКРЕТ-КОРИСТУВАЧА СЕКРЕТНА-МОДЕЛЬ СЕКРЕТ-У-ЧАСІ tokenXXX secret путь журнали закритий subagents agent-x .jsonl Errno Traceback; do
  [[ "$out" == *"$leak"* ]] && bad "у виводі є «$leak» — текст або шлях просочився" || ok "у виводі немає «$leak»"
done

out="$(bash "$SCRIPT" "$T/журнали" --since 2026-09-30 2>&1)"
[[ "$out" != *2026-09-28* && "$out" == *2026-09-30* && "$out" == *2026-10-01* ]] && ok "--since відсікає старші дні, лишає день since і новіші" || bad "--since: $out"
[[ "$out" != *"????"* ]] && ok "--since відсікає записи без дати" || bad "--since лишив запис без дати: $out"
bash "$SCRIPT" "$T/немає" >/dev/null 2>&1
[[ $? == 2 ]] && ok "немає каталогу — exit 2" || bad "немає каталогу — не exit 2"
err="$(bash "$SCRIPT" "$T/немає" 2>&1)"
[[ "$err" != *"$T"* ]] && ok "помилка не друкує шлях" || bad "помилка друкує шлях: $err"
bash "$SCRIPT" "$T/журнали" --since вчора >/dev/null 2>&1
[[ $? == 2 ]] && ok "дивна дата — exit 2" || bad "дивна дата — не exit 2"

# ─── Мутації ───────────────────────────────────────────────────────────────
if [[ -z "${CLAUDE_USAGE_UNDER_TEST:-}" && $fail == 0 ]]; then
  src="$(<"$SCRIPT")"
  n=0
  mutate() {
    local name="$1" from="$2" to="$3" rest m="$T/m$((++n)).sh"
    rest="${src#*"$from"}"
    if [[ "$rest" == "$src" || "$rest" == *"$from"* ]]; then
      bad "мутант «$name»: текст не знайдено рівно один раз — мутація застаріла"
      return
    fi
    printf '%s\n' "${src/"$from"/"$to"}" >"$m"
    if CLAUDE_USAGE_UNDER_TEST="$m" bash "$HERE/$(basename "$0")" >"$m.out" 2>&1; then
      bad "мутант ВИЖИВ: $name"
    else
      ok "мутанта вбито: $name"
    fi
  }
  mutate "повтори id рахуються окремо" 'if mid in calls:' 'if False:'
  mutate "output з першого рядка id, не максимум" 'max(c[4], out)' 'c[4]'
  mutate "день без перевірки на дату" 'DAY_RE.fullmatch(ts[:10])' 'True'
  mutate "модель без перевірки" 'MODEL_RE.fullmatch(model)' 'True'
  mutate "від'ємні токени проходять" 'isinstance(v, int) and v >= 0' 'isinstance(v, int)'
  mutate "порожній рядок — нерозібраний" 'if not line.strip():' 'if False:'
  mutate "запис без дати проходить --since" 'day == UNKNOWN_DAY or ' ''
  mutate "не лише assistant" 'o.get("type") != "assistant"' 'False'
  mutate "контекст без cache_read" ' + num(u, "cache_read_input_tokens")' ''
  mutate "контекст без cache_creation" ' + num(u, "cache_creation_input_tokens")' ''
  mutate "лише верхній рівень каталогу" 'for dirpath, _dirs, files in os.walk(root):' 'for dirpath, _dirs, files in [next(os.walk(root))]:'
  mutate "друкується повний id сесії" 'sid = sid[:8] if' 'sid = sid if'
  mutate "--since не діє" 'day < since' 'False'
  mutate "--since лише один день" 'day < since' 'day != since'
fi

[[ $fail == 1 ]] && {
  echo "FAIL"
  exit 1
}
echo "Усі тести пройдено."
