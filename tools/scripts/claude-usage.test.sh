#!/usr/bin/env bash
# claude-usage.test.sh — підрахунок звернень Claude Code на штучних журналах: лише
# assistant з usage, дублікати id відкидаються, день/сесія/модель, середній контекст,
# --since, і ГОЛОВНЕ — у виводі немає ні тексту повідомлень, ні шляхів.
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
  # Той самий id — повтор блоку відповіді: не рахується, навіть з іншим usage.
  a 2026-09-30 aaaaaaaa-1111-2222-3333-444444444444 m1 claude-opus-5-5 9999 9999 9999 9999
  a 2026-09-30 aaaaaaaa-1111-2222-3333-444444444444 m2 claude-opus-5-5 0 300 100 15
  echo '{"type":"user","timestamp":"2026-09-30T10:00:00Z","sessionId":"aaaaaaaa","message":{"content":"СЕКРЕТ-КОРИСТУВАЧА"}}'
  # Не assistant, хоч і з id та usage (напр. запис прогресу субагента) — пропуск.
  a 2026-09-30 aaaaaaaa-1111-2222-3333-444444444444 m7 claude-opus-5-5 5000 0 0 5000 | sed 's/"type":"assistant"/"type":"progress"/'
  # assistant без usage — пропуск
  echo '{"type":"assistant","timestamp":"2026-09-30T10:00:00Z","sessionId":"aaaaaaaa","message":{"id":"m9","model":"claude-opus-5-5"}}'
  echo 'не json {'
  a 2026-09-28 aaaaaaaa-1111-2222-3333-444444444444 m3 claude-opus-5-5 1 1 1 1
} >"$J/aaaaaaaa.jsonl"
a 2026-10-01 bbbbbbbb-1111-2222-3333-444444444444 m4 claude-sonnet-5-5 20 0 0 7 >"$J/bbbbbbbb.jsonl"
a 2026-10-01 bbbbbbbb-1111-2222-3333-444444444444 m5 claude-haiku-4-5-20251001 4 0 0 1 >"$J/sess-b/subagents/agent-x.jsonl"
echo 'тут теж СЕКРЕТНИЙ-ТЕКСТ' >"$J/notes.txt"

out="$(bash "$SCRIPT" "$T/журнали" 2>&1)"
rc=$?
check() { # check <назва> <регекс рядка виводу>
  if grep -Eq -- "$2" <<<"$out"; then ok "$1"; else bad "$1 — немає рядка /$2/ у виводі:
$out"; fi
}
[[ $rc == 0 ]] && ok "exit 0" || bad "exit $rc: $out"
# m1 (110) і m2 (400): 2 звернення, середній контекст 255, output 20 — повтор m1 не рахується.
check "дублікат id відкинуто, середній контекст і output" '^2026-09-30 +aaaaaaaa +claude-opus-5-5 +2 +255 +20$'
check "інший день — окремий рядок" '^2026-09-28 +aaaaaaaa +claude-opus-5-5 +1 +3 +1$'
check "сесія з двома моделями — по рядку на модель" '^2026-10-01 +bbbbbbbb +claude-sonnet-5-5 +1 +20 +7$'
check "журнал субагента в підтеці — теж рахується" '^2026-10-01 +bbbbbbbb +claude-haiku-4-5-20251001 +1 +4 +1$'
check "РАЗОМ за день" '^2026-10-01 +РАЗОМ +2 +12 +8$'
check "нерозібраний рядок порахований" '^нерозібраних рядків: 1$'
for leak in СЕКРЕТНИЙ СЕКРЕТ-КОРИСТУВАЧА secret путь журнали subagents agent-x .jsonl; do
  [[ "$out" == *"$leak"* ]] && bad "у виводі є «$leak» — текст або шлях просочився" || ok "у виводі немає «$leak»"
done

out="$(bash "$SCRIPT" "$T/журнали" --since 2026-09-30 2>&1)"
[[ "$out" != *2026-09-28* && "$out" == *2026-09-30* ]] && ok "--since відсікає старші дні" || bad "--since: $out"
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
  mutate "дублікати рахуються" ' or mid in seen:' ':'
  mutate "не лише assistant" 'o.get("type") != "assistant"' 'False'
  mutate "контекст без cache_read" ' + num(u, "cache_read_input_tokens")' ''
  mutate "контекст без cache_creation" ' + num(u, "cache_creation_input_tokens")' ''
  mutate "лише верхній рівень каталогу" 'for dirpath, _dirs, files in os.walk(root):' 'for dirpath, _dirs, files in [next(os.walk(root))]:'
  mutate "друкується повний id сесії" 'sid = sid[:8] if' 'sid = sid if'
  mutate "--since не діє" 'if since and day < since:' 'if False:'
fi

[[ $fail == 1 ]] && {
  echo "FAIL"
  exit 1
}
echo "Усі тести пройдено."
