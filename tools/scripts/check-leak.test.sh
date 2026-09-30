#!/usr/bin/env bash
# check-leak.test.sh — оракул витоку: будь-яка адреса блокує, документаційні
# діапазони — лише попередження, рядок із файла відомої адреси блокує завжди і
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
printf '%s\n' '203.0.113.77' 'secret-origin.invalid' '2001:db8::cafe' '2a01:4f8::77' '' >"$KNOWN"

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
expect "loopback — теж блок" 1 "слухає 127.0.0.1" "127.0.0.1"
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

# ─── 3. (в) Документаційні діапазони — попередження, не блок ─────────────────
expect "RFC 5737 192.0.2.0/24" 0 "приклад: 192.0.2.10" "попередження" "RFC 5737" "192.0.2.10"
expect "RFC 5737 198.51.100.0/24" 0 "приклад: 198.51.100.7" "попередження"
expect "RFC 5737 203.0.113.0/24" 0 "приклад: 203.0.113.9" "попередження"
expect "RFC 3849 2001:db8::/32" 0 "приклад: 2001:db8::1" "попередження" "RFC 3849"
expect "RFC 3849 великими, повна" 0 "2001:DB8:0:0:0:0:0:1" "попередження"
expect "поруч із документаційним — сусід 192.0.3.1 не документаційний" 1 "192.0.3.1" "блок"

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
KNOWN_OVERRIDE="secret-value-not-a-path" expect "значення LEAK_ORIGIN_FILE не друкується" 0 \
  "чисто тут" "файла відомої адреси немає" "!secret-value-not-a-path"

KNOWN_OVERRIDE="$T/немає-такого" expect "без файла відомої адреси — попередження, адреси й далі блок" 1 \
  "10.1.2.3" "файла відомої адреси немає" "10.1.2.3"
KNOWN_OVERRIDE="$T/немає-такого" expect "без файла відомої адреси, чистий текст — 0" 0 \
  "чисто тут" "файла відомої адреси немає"

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
  mutate() { # mutate <назва> <було> <стало> — «було» мусить стояти в скрипті рівно раз
    local name="$1" from="$2" to="$3" rest m="$T/mut.$((++n)).sh"
    rest="${src#*"$from"}"
    if [[ "$rest" == "$src" || "$rest" == *"$from"* ]]; then
      bad "мутант «$name»: текст не знайдено рівно один раз — мутація застаріла"
      return
    fi
    printf '%s\n' "${src/"$from"/"$to"}" >"$m"
    if CHECK_LEAK_UNDER_TEST="$m" bash "$HERE/$(basename "$0")" >"$m.out" 2>&1; then
      bad "мутант ВИЖИВ: $name"
    else
      ok "мутанта вбито: $name"
    fi
  }
  n=0
  mutate "будь-який збіг — вихід 0 (вада 2026-09-30)" 'sys.exit(1 if blocked else 0)' 'sys.exit(0)'
  mutate "файл відомої адреси не перевіряється" 'hit = any(p in scan.casefold() for p in known_fold)' 'hit = False'
  mutate "регістр відомого рядка враховується" 'hit = any(p in scan.casefold() for p in known_fold)' 'hit = any(p in scan for p in known)'
  mutate "відомі адреси не порівнюються як адреси" 'if hit or any(is_known(addr) for _, addr in found):' 'if hit:'
  mutate "документаційні діапазони блокують" 'warned.append' 'blocked.append'
  mutate "IPv6 не шукається" 'found += find_ipv6(scan)' 'found += []'
  mutate "IPv4 не шукається" 'for m in IPV4.finditer(scan):' 'for m in []:'
  mutate "IPv6 лише з початку кандидата" 'starts = [0] + [k + 1 for k, c in enumerate(text) if c == ":"]' 'starts = [0]'
  mutate "провідні нулі — не адреса" 'return ipaddress.ip_address(".".join(str(int(x)) for x in parts))' 'return None'
  mutate "markdown-екранування не знімається" 'scan = line.replace("\\.", ".")' 'scan = line'
  mutate "RFC 5737 — лише одна мережа" '("192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24")' '("192.0.2.0/24",)'
  mutate "шлях LEAK_ORIGIN_FILE друкується" 'print("check-leak: попередження — файла відомої адреси немає, правило 1 не діє"' 'print(f"check-leak: попередження — файла відомої адреси немає ({known_path}), правило 1 не діє"'
  mutate "порожні рядки файла відомої адреси лишаються" 'if ln.strip()]' ']'
  mutate "документаційні — лише RFC 5737" '"2001:db8::/32"' '"2001:db8::/128"'
  mutate "вміст відомого рядка друкується" \
    'report(blocked, f, i, "збіг з файлом відомої адреси (вміст не друкується)")' \
    'report(blocked, f, i, "збіг з файлом відомої адреси: " + line.strip())'
  mutate "неіснуючий файл — не помилка" '[[ -f "$f" ]] || {' '[[ -e / ]] || {'
fi

rm -rf "$T"
if [[ $fail == 1 ]]; then
  echo "FAIL"
  exit 1
fi
echo "Усі тести пройдено."
