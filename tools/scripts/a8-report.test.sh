#!/usr/bin/env bash
# a8-report.test.sh — доказ, що звіт збирає те, що обіцяє, і нічого зайвого.
#
# Що СПРАВЖНЄ: сам a8-report.sh, його розбір аргументів, порядок дій і trap.
# Що ПІДМІНЕНО: `ssh`. Заглушка записує КОЖНУ віддалену команду у файл, тож
# перевіряти можна не лише вивід, а й те, що саме скрипт намагався зробити на
# машині. Для звіту, який має бути «переважно на читання», це головне.
#
# Запуск: tools/scripts/a8-report.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/a8-report.sh"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
}

setup() { # setup [режим заглушки]
  ROOT="$(mktemp -d)"
  BIN="$ROOT/bin"
  mkdir -p "$BIN"
  CALLS="$ROOT/ssh-calls"
  : >"$CALLS"
  cat >"$BIN/ssh" <<STUB
#!/usr/bin/env bash
CALLS="$CALLS"
STATE="$ROOT/stop-state"
MODE="\${STUB_MODE:-ok}"
STUB
  cat >>"$BIN/ssh" <<'STUB'
shift          # ім'я хоста
cmd="$*"
echo "$cmd" >>"$CALLS"

# Заглушка тримає стан kill switch, щоб перевірка порядку дій була справжньою,
# а не «скрипт надіслав рядок».
[[ -e "$STATE" ]] || echo OFF >"$STATE"
case "$cmd" in
  *"touch /home/agent/STOP"*) echo ON >"$STATE"; exit 0 ;;
  *"rm -f /home/agent/STOP"*) echo OFF >"$STATE"; exit 0 ;;
  *"test -e /home/agent/STOP"*) cat "$STATE"; exit 0 ;;
esac

case "$cmd" in
  # ВУЗЬКИЙ збіг — саме виклик тіку, а не будь-яка згадка. Широкий `*a8-tick*`
  # ловив також `journalctl -u a8-tick.service`, тобто спрацьовував на третій
  # команді звіту замість тієї, яку перевіряємо (спіймано власним прогоном).
  */usr/local/bin/a8-tick*)
    [[ "$MODE" == tick-dies ]] && exit 1
    exit 0 ;;
  *"tail -1 /home/agent/agent-logs/runs.log"*)
    if [[ "$MODE" == no-killswitch ]]; then
      echo '{"ts":"2026-09-21T22:00:00Z","event":"run","task":"x","result":"ok"}'
    else
      echo '{"ts":"2026-09-21T22:00:00Z","event":"kill_switch","detail":"STOP на місці"}'
    fi
    exit 0 ;;
  *"cat /home/agent/agent-logs/runs.log"*) echo '{"event":"run","task":"log-oracle"}'; exit 0 ;;
  *a8-guard*)   echo "OK: задач сьогодні 1/12, падінь поспіль 2 з 3"; exit 0 ;;
  *a8-egress-rules*) echo "Chain DOCKER-USER (1 references)"; exit 0 ;;
  *ipset*)      echo "Number of entries: 111"; exit 0 ;;
  *list-timers*) echo "NEXT LEFT LAST PASSED UNIT ACTIVATES"; exit 0 ;;
  *journalctl*) echo "Started a8-tick.service"; exit 0 ;;
  *df\ -h*)     echo "/dev/x 226G 27G 188G 13% /"; exit 0 ;;
  *"stat -c"*)  echo "/home/agent/.ssh/id_push власник=agent права=600 розмір=411"; exit 0 ;;
  *) echo "stub-output"; exit 0 ;;
esac
STUB
  chmod +x "$BIN/ssh"
  OUT="$ROOT/report.txt"
}
teardown() { rm -rf "$ROOT"; }
run_report() { PATH="$BIN:$PATH" bash "$SCRIPT" -o "$OUT" "$@" >/dev/null 2>&1; }

# ─── 1. Знімок містить усі обіцяні розділи ────────────────────────────────
setup
run_report
missing=()
for s in "Залізо і памʼять" "Таймери" "Чи запускався тік" "Журнал прогонів" "Запобіжники" \
  "Черга" "Worktree і диск" "Egress" "Креденшал" "Потрібне перезавантаження"; do
  grep -q "$s" "$OUT" || missing+=("$s")
done
((${#missing[@]} == 0)) && ok "знімок містить усі десять розділів" ||
  bad "немає розділів: ${missing[*]}"
teardown

# ─── 2. Без прапорця скрипт НІЧОГО не пише на машині ──────────────────────
# Це головна властивість: звіт можна ганяти будь-коли, зокрема поки демон
# працює, і він не змінить ані стану черги, ані запобіжників.
setup
run_report
if grep -qE 'touch |rm -f |rm |ansible-playbook|a8-tick$|systemctl (start|restart|enable)' "$CALLS"; then
  bad "знімок без --killswitch-test надіслав команду запису: $(grep -nE 'touch |rm |a8-tick$' "$CALLS" | head -2)"
else
  ok "знімок без прапорця не надсилає жодної команди запису"
fi
teardown

# ─── 3. Вміст креденшалів не потрапляє у звіт ─────────────────────────────
# Файл звіту призначений для пересилання. Один `cat` токена зробив би з нього
# витік, тому перевіряємо не текст звіту, а самі НАДІСЛАНІ команди.
setup
run_report
if grep -qE 'cat .*(id_push|push-token)|cat /etc/a8/a8.env$' "$CALLS"; then
  bad "скрипт читає вміст креденшала: $(grep -E 'cat .*(id_push|push-token)' "$CALLS" | head -1)"
else
  ok "креденшали лише через stat/grep — вміст не читається"
fi
grep -q "власник=" "$OUT" && ok "у звіті є права і власник ключа (наявність, не вміст)" ||
  bad "у звіті немає stat-рядка про ключ"
teardown

# ─── 4. Перевірка стоп-крана: виставити → тік → зняти ─────────────────────
setup
run_report --killswitch-test
grep -q "touch /home/agent/STOP" "$CALLS" && grep -q "rm -f /home/agent/STOP" "$CALLS" &&
  ok "перевірка стоп-крана виставляє і знімає його" || bad "не виставив або не зняв STOP"
[[ "$(cat "$ROOT/stop-state")" == OFF ]] &&
  ok "після перевірки kill switch знято — черга вільна" || bad "kill switch лишився ON"
grep -q "ВЕРДИКТ: стоп-кран діє" "$OUT" &&
  ok "вердикт читається однозначно" || bad "немає вердикту: $(grep ВЕРДИКТ "$OUT")"
teardown

# ─── 5. Контроль: якщо тік НЕ дав kill_switch, вердикт не має бути зеленим ─
# Без цього сценарію п.4 доводив би лише те, що скрипт друкує гарний рядок.
setup
STUB_MODE=no-killswitch run_report --killswitch-test
grep -q "ВЕРДИКТ: НЕ ПІДТВЕРДЖЕНО" "$OUT" &&
  ok "тік без kill_switch → вердикт НЕ ПІДТВЕРДЖЕНО" || bad "зелений вердикт на чужому записі"
teardown

# ─── 6. Стоп-кран знімається навіть якщо скрипт помирає посеред перевірки ──
# Найдорожчий сценарій: черга лишилась би на паузі всю ніч, а вранці порожній
# журнал прочитався б як «таймер не працював».
setup
cat >"$BIN/ssh.orig" <"$BIN/ssh"
cat >"$BIN/ssh" <<STUB
#!/usr/bin/env bash
if [[ "\$*" == */usr/local/bin/a8-tick* ]]; then
  echo "\$*" >>"$CALLS"
  echo ON >"$ROOT/stop-state"
  kill -TERM \$PPID       # убиваємо звіт РІВНО між touch і rm
  exit 1
fi
exec bash "$BIN/ssh.orig" "\$@"
STUB
chmod +x "$BIN/ssh"
# Підоболонка з перенаправленням: інакше оболонка тесту друкує власне
# «Terminated» про вбиту дитину і засмічує вивід набору.
(PATH="$BIN:$PATH" bash "$SCRIPT" -o "$OUT" --killswitch-test) >/dev/null 2>&1
[[ "$(cat "$ROOT/stop-state")" == OFF ]] &&
  ok "смерть посеред перевірки → trap усе одно зняв kill switch" ||
  bad "kill switch лишився виставленим після падіння — черга стояла б до ранку"
teardown

# ─── 7. Чужий стоп-кран не чіпається ──────────────────────────────────────
setup
echo ON >"$ROOT/stop-state"
run_report --killswitch-test
grep -q "ПРОПУЩЕНО" "$OUT" && ! grep -q "touch /home/agent/STOP" "$CALLS" &&
  ok "уже виставлений kill switch → перевірка пропускається, чужий стоп не чіпається" ||
  bad "скрипт втрутився в чужий kill switch"
teardown

# ─── 8. Невідомий аргумент — відмова, а не мовчазний знімок ───────────────
setup
PATH="$BIN:$PATH" bash "$SCRIPT" --чого-небудь >/dev/null 2>&1
[[ "$?" == 2 ]] && ok "невідомий аргумент → exit 2" || bad "невідомий аргумент проковтнуто"
teardown

# ─── 9. Шаблон помилок памʼяті: відкидає банер, ловить справжні рядки ─────
# Пара обовʼязкова. Без другої половини шаблон `^НІКОЛИ$` пройшов би перший
# тест і мовчки перестав би ловити будь-що — рівно той клас «зелений результат
# при недієздатному стані», проти якого весь цей набір.
# Рядки не вигадані: банер — зі звіту A8 2026-09-22, CE/UE/mce — сигнатури
# EDAC і MCE з ядра.
RE="$(sed -nE "s/^MEM_ERROR_RE='(.*)'\$/\1/p" "$SCRIPT")"
if [[ -z "$RE" ]]; then
  bad "у скрипті немає MEM_ERROR_RE — тест не перевіряє нічого"
else
  if echo 'EDAC MC: Ver: 3.0.0' | grep -iEq "$RE"; then
    bad "банер версії EDAC читається як помилка памʼяті"
  else
    ok "банер 'EDAC MC: Ver' не видається за помилку"
  fi
  real_ok=1
  while IFS= read -r line; do
    echo "$line" | grep -iEq "$RE" || {
      real_ok=0
      bad "шаблон пропускає справжню помилку: $line"
    }
  done <<'LINES'
EDAC MC0: 1 CE memory read error on CPU_SrcID#0_MC#0
EDAC MC1: 2 UE memory scrubbing error
mce: [Hardware Error]: Machine check events logged
LINES
  ((real_ok)) && ok "справжні сигнатури CE/UE/mce ловляться"
fi

# ─── 10. Журнал читається разом із ротованими файлами ─────────────────────
# Без цього ніч, у яку logrotate спрацював опівночі, читається як «тік не
# працював»: живий runs.log порожній, а записи лежать у .gz.
setup
run_report
grep -q 'zcat' "$CALLS" &&
  ok "журнал читається включно з ротованими (.gz)" ||
  bad "звіт бачить лише живий runs.log — ніч після ротації прочитається як порожня"
teardown

# ─── 11. Осиротілі worktree видно, але скрипт нічого не прибирає ──────────
setup
run_report
grep -q 'worktree prune' "$CALLS" &&
  ok "звіт питає git про осиротілі реєстрації worktree" ||
  bad "осиротіла реєстрація лишиться невидимою — du каже «жодного worktree»"
if grep 'worktree prune' "$CALLS" | grep -qv -- '--dry-run'; then
  bad "звіт надсилає СПРАВЖНІЙ prune: $(grep 'worktree prune' "$CALLS" | head -1)"
else
  ok "prune лише --dry-run — звіт лишається на читання"
fi
teardown

# ─── 12. Розмір worktree рахує agent, а не той, хто зайшов по ssh ─────────
# Структурна половина: глоб має стояти всередині `sudo -u agent bash -c`.
# Поведінку «yurii не читає /home/agent (750)» тут не відтворити — тести
# ідуть під root, який читає все, — тому друга половина перевіряє сам
# внутрішній скрипт: чесний нуль на порожній теці і реальні рядки на повній.
setup
run_report
if grep -qE "sudo -u agent bash -c '[^']*hart-wt/\*" "$CALLS" &&
  ! grep -qE "sudo -u agent du -sh /home/agent/hart-wt/\*" "$CALLS"; then
  ok "глоб worktree розкривається від agent, не від користувача ssh"
else
  bad "глоб worktree поза bash -c — при правах 750 звіт покаже нуль: $(grep -m1 'hart-wt' "$CALLS")"
fi
teardown
WT_DU="$(sed -nE "s/^WT_DU='(.*)'\$/\1/p" "$SCRIPT")"
if [[ -z "$WT_DU" ]]; then
  bad "у скрипті немає WT_DU — поведінку не перевірено"
else
  T="$(mktemp -d)"
  mkdir -p "$T/hart-wt"
  empty="$(bash -c "${WT_DU//\/home\/agent/$T}")"
  mkdir -p "$T/hart-wt/log-oracle" "$T/hart-wt/wall-shelf-registry"
  full="$(bash -c "${WT_DU//\/home\/agent/$T}" | grep -c 'hart-wt/')"
  rm -rf "$T"
  [[ "$empty" == "(жодного worktree)" && "$full" == 2 ]] &&
    ok "порожня тека → «жодного», дві теки → два рядки du" ||
    bad "внутрішній скрипт бреше: порожня='$empty', рядків на двох=$full"
fi

if [[ "$fail" -eq 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
