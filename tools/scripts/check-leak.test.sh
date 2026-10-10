#!/usr/bin/env bash
# check-leak.test.sh — оракул витоку: будь-яка адреса блокує, документаційні
# діапазони й loopback — лише попередження, рядок із файла відомої адреси блокує завжди і
# ніде не друкується; мутації — кожне правило тримається тестом.
# Справжній ~/.flatcraft тест не читає: файл відомої адреси — тимчасовий.
# Запуск: tools/scripts/check-leak.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${CHECK_LEAK_UNDER_TEST:-$HERE/check-leak.sh}"
fail=0
ok() { echo "✓ $1"; }
bad() {
  echo "✗ $1"
  fail=1
  [[ -z "${CHECK_LEAK_UNDER_TEST:-}" ]] || exit 1
}

T="$(mktemp -d)"
KNOWN="$T/origin-host"
# Порожній рядок у кінці — навмисно: `grep -F` з порожнім шаблоном збігся б з усім.
printf '%s\n' '203.0.113.77' 'secret-origin.invalid' '2001:db8::cafe' '2a01:4f8::77' '203.0.77.77' '' >"$KNOWN"

# expect <назва> <очікуваний exit> <текст> [підрядок]... — «!підрядок»: у виводі його
# бути НЕ повинно. Текст пишеться у файл; вивід — stdout і stderr разом.
expect() {
  local name="$1" want="$2" text="$3" out rc needle f="$T/in.md"
  shift 3
  printf '%s\n' "$text" >"$f"
  out="$(LEAK_ORIGIN_FILE="${KNOWN_OVERRIDE:-$KNOWN}" bash "$SCRIPT" "$f" 2>&1)"
  rc=$?
  if [[ $rc != "$want" ]]; then
    bad "$name — очікував exit $want, отримав $rc: $out"
    return
  fi
  for needle in "$@"; do
    if [[ "$needle" == '!'* ]]; then
      [[ "$out" != *"${needle:1}"* ]] || {
        bad "$name — у виводі є «${needle:1}», а не мало бути: $out"
        return
      }
    else
      [[ "$out" == *"$needle"* ]] || {
        bad "$name — у виводі немає «$needle»: $out"
        return
      }
    fi
  done
  ok "$name"
}

# ─── 1. Чисто — вихід 0 ───────────────────────────────────────────────────────
expect "звичайний текст" 0 "Звичайний текст без адрес." "чисто"
expect "версії, час, C++ і MAC — не адреси" 0 \
  "claude 2.1.272, uv 0.12.17; час 14:31:15; std::vector; Foo::Bar; aa:bb:cc:dd:ee:ff" "чисто"
expect "октет понад 255 — не адреса" 0 "300.1.1.1 і 1.2.3.999" "чисто"
expect "порожній рядок у файлі відомої адреси не блокує все" 0 "Будь-який рядок." "чисто"

# ─── 2. (а) Будь-яка адреса — блок (регресія 2026-09-30: оракул завжди виходив з 0)
expect "приватна IPv4" 1 "сервер 10.1.2.3 відповідає" "10.1.2.3" "блок"
expect "публічна IPv4" 1 "DNS 8.8.8.8" "8.8.8.8"
expect "IPv4 у URL з портом" 1 "http://10.0.0.5:8080/health" "10.0.0.5"
expect "IPv4 у кінці речення" 1 "Адреса — 10.9.8.7." "10.9.8.7"
expect "IPv6 стиснена" 1 "вихід через 2a01:4f8:c0c:1::1" "2a01:4f8:c0c:1::1"
expect "IPv6 повна" 1 "2a01:04f8:0c0c:0001:0000:0000:0000:0001" "блок"
expect "документаційна поруч зі справжньою — блок" 1 "192.0.2.1 і 10.1.2.3" "10.1.2.3" "попередження"

# ─── 2а. Пропуски, знайдені рецензією Flash (#170) — кожен мусить блокувати ──
expect "IPv6 з 8 двокрапками, :: у кінці" 1 "адреса 2a01:4f8:c0c:1:2:3:4::" "блок"
expect "IPv6 з 8 двокрапками, :: на початку" 1 "адреса ::1:2:3:4:5:6:7" "блок"
expect "IPv6 впритул після мітки з двокрапкою" 1 "server:2a01:4f8:c0c:1::1" "2a01:4f8:c0c:1::1"
expect "IPv6 після «ipv6:» — друкується сама адреса" 1 "ipv6:2a01:4f8:c0c:1::1" "IPv6 2a01:4f8:c0c:1::1"
expect "IPv4 з провідними нулями" 1 "сервер 10.0.0.01" "блок"
expect "IPv4 з markdown-екрануванням крапок" 1 'сервер 10\.0\.0\.1' "блок"
expect "IPv6 у квадратних дужках з портом" 1 "https://[2a01:4f8:c0c:1::1]:443/" "блок"
expect "C++, Rust і час — досі не адреси" 0 "std::vector, Foo::bar, std::io::Result, 12:00, 14:31:15" "чисто"
expect "голе :: у прозі — не адреса, а ::1 — так" 0 "стиснення \`::\` на початку" "чисто"

# ─── 3. (в) Документаційні діапазони — попередження, не блок ─────────────────
expect "RFC 5737 192.0.2.0/24" 0 "приклад: 192.0.2.10" "попередження" "RFC 5737" "192.0.2.10"
expect "RFC 5737 198.51.100.0/24" 0 "приклад: 198.51.100.7" "попередження"
expect "RFC 5737 203.0.113.0/24" 0 "приклад: 203.0.113.9" "попередження"
expect "RFC 3849 2001:db8::/32" 0 "приклад: 2001:db8::1" "попередження" "RFC 3849"
expect "RFC 3849 великими, повна" 0 "2001:DB8:0:0:0:0:0:1" "попередження"
expect "поруч із документаційним — сусід 192.0.3.1 не документаційний" 1 "192.0.3.1" "блок"

# ─── 3а. Loopback — попередження (рішення yurii 2026-10-09, #222) ─────────────
# Адреси loopback будуються з частин під час запуску (рішення yurii 2026-10-09): у
# тексті файла літералу немає, тож тест публікується й чинним check-leak з main.
lo4="$(printf '%s.%s.%s.%s' 127 0 0 1)"
lo4lo="$(printf '%s.%s.%s.%s' 127 0 0 0)"
lo4hi="$(printf '%s.%s.%s.%s' 127 255 255 254)"
lo4z="$(printf '%s.%s.%s.%s' 127 000 000 001)"
lo6="$(printf '%s%s' '::' 1)"
lo6full="$(printf '%s:%s:%s:%s:%s:%s:%s:%s' 0 0 0 0 0 0 0 1)"
expect "loopback IPv4 — попередження, не блок" 0 "слухає $lo4" "попередження" "$lo4 — loopback" "чисто"
expect "loopback — увесь 127/8, нижній і верхній край" 0 "$lo4lo і $lo4hi" "$lo4lo — loopback" "$lo4hi — loopback"
expect "loopback з провідними нулями" 0 "слухає $lo4z" "loopback" "чисто"
expect "loopback з портом і в URL" 0 "http://$lo4:8080/health" "loopback"
expect "loopback з портом через крапку (tcpdump)" 0 "IP $lo4.51234 > $lo6: UDP" "loopback" "чисто"
expect "loopback з markdown-екрануванням і дефангом" 0 "${lo4//./\\.} і ${lo4//./[.]}" "loopback" "чисто"
expect "IPv6 loopback — попередження" 0 "слухає $lo6" "$lo6 — loopback" "чисто"
lo4map="$(printf '%s:%s:%s:%s' '' '' ffff "$lo4")"
expect "IPv4-mapped loopback окремо — блок" 1 "адреса $lo4map" "блок" "!loopback, не блок"
expect "IPv4-mapped loopback упритул після літери — блок (регресія #225)" 1 "адресаv$lo4map" "блок" "!loopback, не блок"
expect "IPv4-compatible loopback упритул після літери — блок" 1 "$(printf 'r%s%s' '::' "$lo4")" "блок"
expect "IPv4 loopback після мітки з двокрапкою — блок (у бік блоку)" 1 "host:$lo4" "блок"
expect "IPv6 loopback повністю і в дужках з портом" 0 "$lo6full і [$lo6]:8080" "loopback" "чисто"
lo4oct="$(printf '%s.%s.%s.%s' 0177 0 0 1)"
lo4short="$(printf '%s.%s' 127 1)"
expect "вісімковий loopback (частина з чотирьох цифр) — не розпізнається (межа шапки), чисто" 0 "адреса $lo4oct" "чисто"
expect "скорочений loopback з двох частин — не розпізнається (межа шапки), чисто" 0 "адреса $lo4short" "чисто"
# Сусідні діапазони, приватні й link-local — у тест не пишемо: тест публікується через
# check-leak, а там вони блок. Приватні й публічні адреси як блок тримають розділ 2 і
# мутант «усі адреси — попередження»; межі мереж loopback — мутанти нижче.
expect "loopback поруч з відомою адресою — блок" 1 "$lo4 і 203.0.113.77" "файлом відомої адреси" "!203.0.113.77"

# ─── 4. (б) Файл відомої адреси — блок завжди, вміст не друкується ──────────
expect "відома адреса з документаційного діапазону — все одно блок" 1 \
  "origin 203.0.113.77 тут" "файлом відомої адреси" "!203.0.113.77"
expect "відоме ім'я хоста — блок" 1 \
  "curl https://secret-origin.invalid/" "файлом відомої адреси" "!secret-origin.invalid"
expect "відома адреса поруч з іншою документаційною — вміст рядка не друкується" 1 \
  "203.0.113.77 і 192.0.2.5" "!203.0.113.77"

expect "відоме ім'я хоста в іншому регістрі — блок" 1 \
  "https://Secret-Origin.INVALID/" "файлом відомої адреси" "!Secret-Origin" "!secret-origin"
expect "відома документаційна IPv6 в іншому регістрі — блок, не попередження" 1 \
  "адреса 2001:DB8::CAFE" "файлом відомої адреси" "!CAFE" "!cafe"
expect "відома IPv6 в іншому записі — блок і не друкується" 1 \
  "адреса 2a01:04f8:0:0:0:0:0:77" "файлом відомої адреси" "!2a01:04f8" "!2a01:4f8::77"
KNOWN_OVERRIDE="secret-value-not-a-path" expect "значення LEAK_ORIGIN_FILE не друкується" 3 \
  "чисто тут" "файл відомої адреси недоступний" "!secret-value-not-a-path"

KNOWN_OVERRIDE="$T/немає-такого" expect "без файла відомої адреси — адреси й далі блок" 1 \
  "10.1.2.3" "файл відомої адреси недоступний" "10.1.2.3"
KNOWN_OVERRIDE="$T/немає-такого" expect "без файла відомої адреси, чистий текст — 3, не «чисто»" 3 \
  "чисто тут" "не перевірено"

# ─── 4а. Контрприклади окремої сесії Claude (#170) ────────────────────────────
expect "IPv4 з портом через крапку (tcpdump)" 1 "IP 10.0.0.5.51234 > 8.8.8.8.53: UDP" "10.0.0.5"
expect "IPv4 після «цифра.»" 1 "ver1.8.8.8.8" "8.8.8.8"
expect "дефанг [.]" 1 "10[.]0[.]0[.]1" "блок"
expect "відомий хост з markdown-екрануванням \\-" 1 'secret\-origin.invalid' "файлом відомої адреси"
expect "відомий хост з екрануванням \\." 1 'secret-origin\.invalid' "файлом відомої адреси"
expect "відома IPv4 як IPv4-mapped IPv6 — блок і не друкується" 1 "адреса ::ffff:cb00:4d4d" "файлом відомої адреси" "!cb00"
expect "відома IPv4 як NAT64 — блок і не друкується" 1 "адреса 64:ff9b::cb00:4d4d" "файлом відомої адреси" "!64:ff9b"
expect "відома IPv4 як 6to4 — блок і не друкується" 1 "адреса 2002:cb00:4d4d::1" "файлом відомої адреси" "!2002:"
expect "Rust і C++ зі шляхами модулів — не адреси" 0 "crate::a::b, ::add_one(), my_d::bad_alloc, x.c_str()" "чисто"
printf '\xff\xfe сміття 10.1.2.3\n' >"$T/bad-utf8.md"
out="$(LEAK_ORIGIN_FILE="$KNOWN" bash "$SCRIPT" "$T/bad-utf8.md" 2>&1)"
rc=$?
if [[ $rc == 1 && "$out" != *Traceback* ]]; then ok "невалідний UTF-8 у тексті — блок без краху"; else bad "невалідний UTF-8 — rc=$rc: $out"; fi

# Файл відомої адреси в незвичному вигляді: BOM, прикраси, CRLF, UTF-16, порожній.
printf '\xef\xbb\xbfbom-host.invalid\n' >"$T/k-bom"
KNOWN_OVERRIDE="$T/k-bom" expect "BOM на початку файла відомої адреси" 1 "https://bom-host.invalid/" "файлом відомої адреси" "!bom-host"
printf '%s\n' '203.0.113.88 # origin' 'deploy@198.51.100.9:22' '192.0.2.44/32' >"$T/k-decor"
KNOWN_OVERRIDE="$T/k-decor" expect "відома адреса з коментарем у файлі — блок, не попередження" 1 "адреса 203.0.113.88" "файлом відомої адреси" "!203.0.113.88"
KNOWN_OVERRIDE="$T/k-decor" expect "відома адреса з user@ і портом у файлі" 1 "адреса 198.51.100.9" "файлом відомої адреси" "!198.51.100.9"
KNOWN_OVERRIDE="$T/k-decor" expect "відома адреса з CIDR у файлі" 1 "адреса 192.0.2.44" "файлом відомої адреси" "!192.0.2.44"
printf '  crlf-host.invalid  \r\n' >"$T/k-crlf"
KNOWN_OVERRIDE="$T/k-crlf" expect "CRLF і пробіли у файлі відомої адреси" 1 "https://crlf-host.invalid/" "файлом відомої адреси"
printf 'utf16-host.invalid\n' | iconv -t UTF-16 >"$T/k-utf16"
KNOWN_OVERRIDE="$T/k-utf16" expect "файл відомої адреси в UTF-16 — 3 без traceback і шляху" 3 "чисто тут" "недоступний" "!Traceback" "!k-utf16"
printf '\n  \n' >"$T/k-empty"
KNOWN_OVERRIDE="$T/k-empty" expect "порожній файл відомої адреси — 3, а не «чисто»" 3 "чисто тут" "не перевірено"
KNOWN_OVERRIDE="none" expect "LEAK_ORIGIN_FILE=none — правило 1 свідомо вимкнено, чисто — 0" 0 "чисто тут" "правило 1 вимкнено"
KNOWN_OVERRIDE="none" expect "LEAK_ORIGIN_FILE=none — адреси й далі блок" 1 "10.1.2.3" "блок"

# ─── 5. Кілька файлів і помилки виклику ──────────────────────────────────────
printf 'чисто\n' >"$T/a.md"
printf 'адреса 10.1.2.3\n' >"$T/b.md"
out="$(LEAK_ORIGIN_FILE="$KNOWN" bash "$SCRIPT" "$T/a.md" "$T/b.md" 2>&1)"
rc=$?
if [[ $rc == 1 && "$out" == *"b.md:1"* ]]; then ok "два файли, брудний другий — блок, з іменем файла і рядком"; else bad "два файли — rc=$rc: $out"; fi
out="$(bash "$SCRIPT" 2>&1)"
rc=$?
if [[ $rc == 2 ]]; then ok "без аргументів — exit 2"; else bad "без аргументів — rc=$rc: $out"; fi
out="$(LEAK_ORIGIN_FILE="$KNOWN" bash "$SCRIPT" "$T/немає.md" 2>&1)"
rc=$?
if [[ $rc == 2 ]]; then ok "неіснуючий файл — exit 2, а не «чисто»"; else bad "неіснуючий файл — rc=$rc: $out"; fi

# ─── 6. Мутації: кожне правило тримається тестом ────────────────────────────
if [[ -z "${CHECK_LEAK_UNDER_TEST:-}" && $fail == 0 ]]; then
  src="$(<"$SCRIPT")"
  printf 'Звичайний опис PR без адрес.\n' >"$T/clean.md"
  mutate() { # mutate <назва> <було> <стало> — «було» мусить стояти в скрипті рівно раз
    local name="$1" from="$2" to="$3" rest m="$T/mut.$((++n)).sh"
    rest="${src#*"$from"}"
    if [[ "$rest" == "$src" || "$rest" == *"$from"* ]]; then
      bad "мутант «$name»: текст не знайдено рівно один раз — мутація застаріла"
      return
    fi
    printf '%s\n' "${src/"$from"/"$to"}" >"$m"
    # Мутант мусить бути живим: на чистому тексті — вихід 0, 1 або 3 і без traceback.
    # Інакше його «вбив» би будь-який збій (синтаксична помилка python), а не сценарій
    # його правила.
    LEAK_ORIGIN_FILE="$KNOWN" bash "$m" "$T/clean.md" >"$m.clean" 2>&1
    local crc=$?
    if [[ $crc != [013] ]] || grep -qE 'Traceback|SyntaxError' "$m.clean"; then
      bad "мутант «$name» нежиттєздатний (exit $crc): $(tail -1 "$m.clean")"
      return
    fi
    if CHECK_LEAK_UNDER_TEST="$m" bash "$HERE/$(basename "$0")" >"$m.out" 2>&1; then
      bad "мутант ВИЖИВ: $name"
    else
      ok "мутанта вбито: $name"
    fi
  }
  n=0
  mutate "будь-який збіг — вихід 0 (вада 2026-09-30)" \
    '    print(f"check-leak: блок — знайдено {len(blocked)}; публікувати не можна")
    sys.exit(1)' \
    '    print(f"check-leak: блок — знайдено {len(blocked)}; публікувати не можна")
    sys.exit(0)'
  mutate "без файла відомої адреси — «чисто»" \
    '    print("check-leak: не перевірено — без файла відомої адреси публікувати не можна")
    sys.exit(3)' \
    '    print("check-leak: не перевірено — без файла відомої адреси публікувати не можна")
    sys.exit(0)'
  mutate "файл відомої адреси не перевіряється" 'hit = any(p in scan.casefold() for p in known_fold)' 'hit = False'
  mutate "регістр відомого рядка враховується" 'hit = any(p in scan.casefold() for p in known_fold)' 'hit = any(p in scan for p in known)'
  mutate "відомі адреси не порівнюються як адреси" 'if hit or any(forms(addr) & known_ips for _, addr in found):' 'if hit:'
  mutate "адреси з прикрашених рядків відомого файла не беруться" '        for _, a in find_ipv4(nk) + find_ipv6(nk):' '        for _, a in []:'
  mutate "BOM з'їдає перший рядок відомого файла" 'encoding="utf-8-sig"' 'encoding="utf-8"'
  mutate "LEAK_ORIGIN_FILE=none не вимикає правило" 'if known_path == "none":' 'if False:'
  mutate "IPv4-mapped і 6to4 не розпізнаються" '        for v4 in (addr.ipv4_mapped, addr.sixtofour):' '        for v4 in ():'
  mutate "NAT64 не розпізнається" 'if addr in NAT64 or (addr in V4_COMPAT and int(addr) > 1):' 'if False:'
  mutate "документаційні діапазони блокують" 'warned.append(f"{f}:{i}: {text} — документаційний' 'blocked.append(f"{f}:{i}: {text} — документаційний'
  mutate "RFC 5737 — лише одна мережа" '("192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24")' '("192.0.2.0/24",)'
  mutate "документаційні — без RFC 3849" '"2001:db8::/32"' '"2001:db8::/128"'
  mutate "loopback — блок (як до 2026-10-09)" 'elif any(addr in n for n in LOOPBACK_NETS)' 'elif False'
  mutate "усі адреси — попередження" 'report(blocked, f, i, f"IPv{addr.version} {text}")' 'warned.append(f"IPv{addr.version} {text}")'
  mutate "loopback IPv4 — лише одна адреса" 'IPv4Network((127 << 24, 8))' 'IPv4Network(((127 << 24) + 1, 32))'
  mutate "loopback — увесь IPv4" 'elif any(addr in n for n in LOOPBACK_NETS)' 'elif (addr.version == 4 or any(addr in n for n in LOOPBACK_NETS))'
  mutate "IPv6 loopback — не loopback" 'IPv6Network((1, 128))' 'IPv6Network((2, 128))'
  mutate "loopback — увесь IPv6" 'elif any(addr in n for n in LOOPBACK_NETS)' 'elif (addr.version == 6 or any(addr in n for n in LOOPBACK_NETS))'
  mutate "loopback після двокрапки — попередження" 'and text not in v6_tails:' ':'
  mutate "IPv6 не шукається" '            found = find_ipv4(scan) + find_ipv6(scan)' '            found = find_ipv4(scan)'
  mutate "IPv4 не шукається" '            found = find_ipv4(scan) + find_ipv6(scan)' '            found = find_ipv6(scan)'
  mutate "IPv4 — лише перше вікно з чотирьох частин" '        for k in range(len(parts) - 3):' '        for k in range(min(1, len(parts) - 3)):'
  mutate "IPv6 лише з початку кандидата" 'starts = [0] + [k + 1 for k, c in enumerate(text) if c == ":"]' 'starts = [0]'
  mutate "IPv6 може починатися після ::" '            if s >= 2 and text[s - 2 : s] == "::":' '            if False:'
  mutate "ліва межа IPv6 не перевіряється" 'if s < covered or (t0 + s > 0 and word_char(line[t0 + s - 1])):' 'if s < covered:'
  mutate "права межа IPv6 не перевіряється" '                if t0 + end < len(line) and word_char(line[t0 + end]):' '                if False:'
  mutate "_ — не частина слова" '    return c.isalnum() or c == "_"' '    return c.isalnum()'
  mutate "кандидат без hex-цифри — адреса" 'if not re.search(r"[0-9A-Fa-f]", cand):' 'if False:'
  mutate "провідні нулі — не адреса" 'return ipaddress.ip_address(".".join(str(int(x)) for x in parts))' 'return None'
  mutate "екранування й дефанг не знімаються" \
    'return line.replace("\\.", ".").replace("\\-", "-").replace("\\_", "_").replace("[.]", ".")' 'return line'
  mutate "порожні рядки файла відомої адреси лишаються" 'known = [ln.strip() for ln in fh if ln.strip()]' 'known = [ln.strip() for ln in fh]'
  mutate "вміст відомого рядка друкується" \
    'report(blocked, f, i, "збіг з файлом відомої адреси (вміст не друкується)")' \
    'report(blocked, f, i, "збіг з файлом відомої адреси: " + line.strip())'
  mutate "шлях LEAK_ORIGIN_FILE друкується" \
    'print("check-leak: файл відомої адреси недоступний (немає, не читається або порожній) — правило 1 не перевірено", file=sys.stderr)' \
    'print(f"check-leak: файл відомої адреси недоступний ({known_path}) — правило 1 не перевірено", file=sys.stderr)'
  mutate "невалідний UTF-8 у тексті — крах" 'encoding="utf-8", errors="replace"' 'encoding="utf-8"'
  mutate "неіснуючий файл — не помилка" '[[ -f "$f" ]] || {' '[[ -e / ]] || {'
fi

rm -rf "$T"
if [[ $fail == 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
