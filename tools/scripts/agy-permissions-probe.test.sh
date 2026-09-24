#!/usr/bin/env bash
# agy-permissions-probe.test.sh — доказ, що зонд робить правильний висновок.
#
# Що СПРАВЖНЄ: сам зонд, його промпти, файли, які він створює, і розбір логу.
# Що ПІДМІНЕНО: agy — заглушка, що відмовляє так само, як справжній (виміряно
# 2026-09-24): без правила allow — рядок логу `soft-denying tool confirmation
# "<інструмент>"` з тими самими назвами (ViewFile, WriteToFile,
# ReplaceFileContent, RunCommand); за правилом deny — помилка інструмента у
# відповіді «…write_file(…). Matches user-configured deny rule.» Налаштування
# agy — фікстура. Стани: відкритий, закритий, закритий з однією діркою,
# команда в конфігу, «прочитав і спіткнувся на іншому», мовчазна модель,
# тайм-аут.
#
# Запуск: tools/scripts/agy-permissions-probe.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROBE="$HERE/agy-permissions-probe.sh"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
}

T="$(mktemp -d)"
trap 'rm -rf "$T" "$T-wt"' EXIT
git -C "$T" init -q
mkdir -p "$T/docs/promts/inputs" "$T/bin" "$T/out" "$T/home" "$T-wt"
echo '{"permissions":{"allow":["read_file(/x)","write_file(/x/docs/promts/inputs)"]}}' >"$T/closed.json"
echo '{"permissions":{"allow":["command(ls)","read_file(*)","write_file(*)"]}}' >"$T/open.json"
echo '{"permissions":{"allow":["read_file(/x)","write_file(/x/docs/promts/inputs)","command(bash)"]}}' >"$T/cfgcmd.json"

cat >"$T/bin/agy" <<'STUB'
#!/usr/bin/env bash
# Заглушка agy. STUB_MODE: open | closed | silent | wsilent | timeout | wrongtool;
# STUB_HOLE — одна дірка в закритому режимі.
prompt="$2"; log=""
while (($#)); do [[ "$1" == --log-file ]] && log="$2"; shift; done
echo 'Propagating selected model override to backend: label="Stub"' >"$log"
[[ "$STUB_MODE" == timeout ]] && exit 124
soft() { echo "I0924 tool_confirmation_manager.go:211] Print mode: soft-denying tool confirmation \"$1\" at step 2" >>"$log"; echo 'jetski: no output produced'; }
path() { grep -o "/[^ ]*$1[^ ]*" <<<"$prompt" | head -1; }
allowed() { [[ "$STUB_MODE" == open || "$STUB_HOLE" == "$1" ]]; }
quiet() { [[ "$STUB_MODE" == silent || ("$STUB_MODE" == wsilent && "$1" != cmd) ]]; }
copy_to() { # copy_to <джерело> <ціль>
  sed -n 's/^Секретне слово: //p' "$1" >"$2"
}
if [[ "$prompt" == *_agy-probe-link-* ]]; then
  allowed slink && copy_to "$(path _agy-probe-link-)" "$(path _agy-probe-slink-)" || { quiet slink || soft ViewFile; }
elif [[ "$prompt" == *agy-probe-src-* ]]; then
  src="$(path agy-probe-src-)"
  dst="$(grep -o '/[^ ]*_agy-probe-[a-z]*-[^ ]*' <<<"$prompt" | grep -v -- -src- | head -1)"
  if [[ "$src" == *-wt/* && "$STUB_HOLE" == nowt ]]; then soft ViewFile; exit 0; fi
  if [[ "$src" == "$HOME"/* ]]; then
    # «прочитав і спіткнувся на іншому»: читання вдалося, запису немає, відмова — іншому інструменту
    if [[ "$STUB_MODE" == wrongtool ]]; then soft RunCommand; exit 0; fi
    allowed rhome || { quiet rhome || soft ViewFile; exit 0; }
  fi
  copy_to "$src" "$dst"
elif [[ "$prompt" == *.agy-probe-write-* ]]; then
  allowed whome && echo x >"$(path .agy-probe-write-)" || { quiet whome || soft WriteToFile; }
elif [[ "$prompt" == *agy-probe-vartmp-* ]]; then
  allowed vartmp && echo x >"$(path agy-probe-vartmp-)" || { quiet vartmp || soft WriteToFile; }
elif [[ "$prompt" == *agy-probe-tmp-* ]]; then
  if [[ "$STUB_MODE" == wrongdeny ]]; then echo "Permission denied for read_file(/etc/x). Matches user-configured deny rule."
  elif allowed tmp; then echo x >"$(path agy-probe-tmp-)"
  else quiet tmp || echo "Permission denied for write_file($(path agy-probe-tmp-)). Matches user-configured deny rule."; fi
elif [[ "$prompt" == *inputs-sibling-* ]]; then
  allowed sib && echo x >"$(path inputs-sibling-)" || { quiet sib || soft WriteToFile; }
elif [[ "$prompt" == *_agy-probe-edit-* ]]; then
  f="$(path _agy-probe-edit-)"
  allowed edit && sed -i 's/original-/changed-/' "$f" || { quiet edit || soft ReplaceFileContent; }
else
  allowed cmd && ls "$(path agy-probe-ls-)" || { quiet cmd || soft RunCommand; }
fi
STUB
chmod +x "$T/bin/agy"

probe() { # probe <режим> [дірка] [фікстура налаштувань]
  local cfg="${3:-$T/closed.json}"
  [[ "$1" == open ]] && cfg="$T/open.json"
  (cd "$T" && HOME="$T/home" STUB_MODE="$1" STUB_HOLE="${2:-}" AGY="$T/bin/agy" AGY_SETTINGS="$cfg" PROBE_OUT_DIR="$T/out" bash "$PROBE" 2>&1)
}
line() { grep -E "^$1 " <<<"$2" | tr -s ' '; }

out="$(probe closed)"
[[ $? == 0 && "$out" == *"звужено"* && "$(line READ_WT "$out")" == "READ_WT працює (має працювати)" ]] &&
  ok "закритий конфіг → код 0, читання репо й worktree працює" || bad "закритий конфіг: $out"

out="$(probe open)"
rc=$?
opened="$(grep -c 'ВІДКРИТО' <<<"$out")"
[[ $rc == 1 && "$opened" == 9 ]] && ok "відкритий конфіг (контроль) → код 1, усі дев'ять заборонених «ВІДКРИТО»" ||
  bad "відкритий конфіг розпізнано неправильно (rc=$rc, відкритих $opened з 9): $out"

for hole in tmp vartmp sib rhome slink edit; do
  case $hole in tmp) name=WRITE_TMP ;; vartmp) name=WRITE_VARTMP ;; sib) name=WRITE_SIBLING ;;
    rhome) name=READ_HOME ;; slink) name=READ_SYMLINK ;; edit) name=EDIT_REPO ;; esac
  out="$(probe closed "$hole")"
  rc=$?
  if [[ $rc == 1 && "$(line "$name" "$out")" == "$name ВІДКРИТО (має бути заблоковано)" && "$(grep -c 'ВІДКРИТО' <<<"$out")" == 1 ]]; then
    ok "одна дірка ($name) при закритому решті → код 1, видно саме її"
  else
    bad "дірку $name не розпізнано (rc=$rc): $out"
  fi
done

# Контрприклад Flash №1: зонд пробує лише ls, а в конфігу дозволено іншу команду.
out="$(probe closed "" "$T/cfgcmd.json")"
[[ $? == 1 && "$(line CFG "$out")" == "CFG ВІДКРИТО (має бути заблоковано)" && "$out" == *"command(bash)"* ]] &&
  ok "command(bash) у конфігу при відхиленому ls → код 1, CFG «ВІДКРИТО» з назвою команди" ||
  bad "команду в конфігу не помічено: $out"

# Контрприклад Flash №2: прочитав домашній файл, запису немає, відмова іншому інструменту.
out="$(probe wrongtool)"
[[ $? == 2 && "$(line READ_HOME "$out")" == "READ_HOME НЕМАЄ ДАНИХ (має бути заблоковано)" ]] &&
  ok "відмова ІНШОМУ інструменту не зараховується як блокування читання → код 2" ||
  bad "чужа відмова зарахована як блокування: $out"

# Відмова deny для ІНШОГО дозволу (read_file) не доводить, що заблоковано запис.
out="$(probe wrongdeny)"
[[ $? == 2 && "$(line WRITE_TMP "$out")" == "WRITE_TMP НЕМАЄ ДАНИХ (має бути заблоковано)" ]] &&
  ok "deny для іншого дозволу не зараховується як блокування запису → код 2" ||
  bad "чужий deny зараховано як блокування запису: $out"

# Звуження, що зламало читання worktree-ів, — теж провал: без нього agy не
# прочитає код гілки на рецензії.
out="$(probe closed nowt)"
[[ $? == 1 && "$(line READ_WT "$out")" == "READ_WT НЕ працює (має працювати)" ]] &&
  ok "читання worktree-ів заблоковано → код 1: звуження не має ламати рецензію" ||
  bad "зламане читання worktree не помічено: $out"

out="$(probe silent)"
[[ $? == 2 && "$out" == *"не пробувала"* ]] && ok "модель нічого не пробувала → код 2, а не «заблоковано»" ||
  bad "мовчазна модель дала хибний висновок: $out"

out="$(probe wsilent)"
[[ $? == 2 && "$(line WRITE_HOME "$out")" == "WRITE_HOME НЕМАЄ ДАНИХ (має бути заблоковано)" ]] &&
  ok "модель не пробувала запис, а команду відхилено → код 2" || bad "непроба запису зарахована як блокування: $out"

out="$(probe timeout)"
[[ $? == 2 && "$out" == *"не відповів"* ]] && ok "тайм-аут → код 2, «висновку немає»" || bad "тайм-аут: $out"

left="$(find "$T/docs" "$T/home" "$T-wt" -name '*probe*' 2>/dev/null | wc -l)"
[[ "$left" == 0 ]] && ok "після зондів не лишилось жодного файла зонду (і посилання теж)" ||
  bad "лишились файли зонду: $(find "$T/docs" "$T/home" "$T-wt" -name '*probe*' 2>/dev/null)"

if ((fail)); then
  echo "Провалено."
  exit 1
fi
echo "Усі тести пройдено."
