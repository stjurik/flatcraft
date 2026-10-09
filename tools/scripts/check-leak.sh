#!/usr/bin/env bash
# check-leak.sh — оракул витоку перед публікацією: опис PR, коментар, issue, файл.
#
# ЧОМУ ЦЕ ІСНУЄ. Репозиторій публічний, а оркестратор щодня публікує тексти, зокрема
# дослівні вердикти рецензентів, яких він не писав. Адреса сервера в такому тексті —
# витік. До 2026-09-30 перевірка жила в пісочниці сесії, поза git (а конфігурації
# поза git не існує, CLAUDE.md §0 п.5), і завжди виходила з 0. Тож
# `перевірка файл && gh pr comment …` нічого не зупиняла: коментар до #159 пішов
# попри знайдений збіг.
#
# ПРАВИЛА (рішення yurii 2026-09-30):
#   1. Рядок із файла відомої адреси — БЛОК завжди, навіть якщо адреса з
#      документаційного діапазону. Вміст файла і рядок зі збігом не друкуються —
#      той самий оракул, що в Master Run 16 (`grep -cFf … → 0`).
#   2. Будь-яка інша IPv4 чи IPv6 адреса, зокрема приватні й link-local, — БЛОК.
#   3. Документаційні діапазони — ПОПЕРЕДЖЕННЯ, не блок: RFC 5737 (192.0.2.0/24,
#      198.51.100.0/24, 203.0.113.0/24) і RFC 3849 (2001:db8::/32). Їх пишуть у
#      прикладах навмисно.
#   4. Loopback — ПОПЕРЕДЖЕННЯ, не блок (рішення yurii 2026-10-09, #222; до того —
#      блок за правилом 2): мережа 127/8 і IPv6 loopback (/128). Це не адреса машини, а її пишуть у
#      тестах і вердиктах (зупинка #221). Loopback, записаний як IPv4-mapped IPv6,
#      лишається блоком: рішенням названо лише ці два діапазони.
#
# Що ще ловить (рецензія #170, Flash і окрема сесія Claude): регістр і BOM у файлі
# відомої адреси, адреси з «прикрашених» рядків (`# коментар`, `user@`, `:порт`,
# `/32`), відому IPv4 у записах IPv6 (mapped, 6to4, NAT64), markdown-екранування й
# дефанг `[.]`, IPv4 з провідними нулями, `IP.порт` з tcpdump.
#
# ЧОГО НЕ ДОВОДИТЬ.
#   - Секрети взагалі (токени, ключі) й імена машин — лише адреси й рядки відомого файла.
#   - Рідкісні записи IPv4: ціле (2130706433), шістнадцяткове (0x7f000001),
#     вісімкове як таке (0177.0.0.1 не розпізнається зовсім: частина з чотирьох цифр;
#     тризначні частини з нулем попереду читаються як десяткові), скорочене (127.1).
#   - IPv6 впритул після літери (`адреса2a01:…`) — межу слова не перейти без
#     хибних тривог на коді.
#   - Помилка в бік блоку: версія з чотирьох чисел (6.6.87.2) і вісім hex-байтів
#     через двокрапку (WWN) — теж «адреси».
#   - Механічно перевірку ніщо не вмикає: її запускає оркестратор перед `gh`.
#
# Використання: tools/scripts/check-leak.sh <файл>...
#   LEAK_ORIGIN_FILE — файл відомої адреси, по одному шаблону в рядку
#                      (дефолт ~/.flatcraft/leak/origin-host);
#                      `none` — свідомо без правила 1 (чиста копія, хмарна сесія).
# Вихід: 0 — чисто (попередження можливі); 1 — блок; 2 — помилка виклику;
#        3 — не перевірено: файл відомої адреси недоступний (немає, не читається,
#        порожній). 3, а не 0: перевірка, що мовчки пропускає без конфігурації, —
#        та сама вада, що до 2026-09-30.
set -uo pipefail

if [[ $# -eq 0 ]]; then
  echo "check-leak: вкажіть файли для перевірки" >&2
  exit 2
fi
for f in "$@"; do
  [[ -f "$f" ]] || {
    echo "check-leak: немає файла «$f» — перевіряти нічого, це не «чисто»" >&2
    exit 2
  }
done

exec python3 - "${LEAK_ORIGIN_FILE:-$HOME/.flatcraft/leak/origin-host}" "$@" <<'PY'
import ipaddress
import re
import sys

known_path, files = sys.argv[1], sys.argv[2:]

DOC_NETS = {
    "RFC 5737": [ipaddress.ip_network(n) for n in ("192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24")],
    "RFC 3849": [ipaddress.ip_network(n) for n in ("2001:db8::/32",)],
}
# Рішення yurii 2026-10-09 (#222): loopback — попередження, як документаційні.
# Мережі задано числами, а не записом адреси: цей файл публікується через check-leak.
LOOPBACK_NETS = [ipaddress.IPv4Network((127 << 24, 8)), ipaddress.IPv6Network((1, 128))]
NAT64 = ipaddress.ip_network("64:ff9b::/96")
V4_COMPAT = ipaddress.ip_network("::/96")

# IPv4 — будь-яке вікно з чотирьох частин у послідовності чисел через крапку. Так
# `10.0.0.5.51234` (tcpdump) і `ver1.8.8.8.8` дають адресу, а версія 2.1.272 —
# ні: у ній лише три частини. Перша версія з межами «не .цифра» пропускала їх (#170).
DOTTED = re.compile(r"(?<![0-9])[0-9]+(?:\.[0-9]+){3,}")
# Кандидат IPv6 — послідовність hex-цифр, двокрапок і крапок; саму адресу в ньому
# шукає find_ipv6.
V6_TOKEN = re.compile(r"[0-9A-Fa-f:.]+")


def word_char(c):
    # `_` — теж частина слова: інакше `my_d::bad_alloc` і `::add_one` стали б адресами.
    return c.isalnum() or c == "_"


def parse_ip(text):
    """Адреса або None. IPv4 з провідними нулями (10.0.0.01) — теж адреса: ping і
    curl її розуміють, хоча ipaddress відмовляє."""
    try:
        return ipaddress.ip_address(text)
    except ValueError:
        pass
    parts = text.split(".")
    if len(parts) == 4 and all(re.fullmatch(r"[0-9]{1,3}", x) and int(x) <= 255 for x in parts):
        return ipaddress.ip_address(".".join(str(int(x)) for x in parts))
    return None


def find_ipv4(line):
    out = []
    for m in DOTTED.finditer(line):
        parts = m.group(0).split(".")
        for k in range(len(parts) - 3):
            text = ".".join(parts[k : k + 4])
            addr = parse_ip(text)
            if addr is not None:
                out.append((text, addr))
    return out


def find_ipv6(line):
    """(текст, адреса) для кожної IPv6 у рядку.

    Адреса починається на початку кандидата або одразу після одинарної двокрапки
    (`server:2a01:…`), але не після `::` (`crate::a::b` — шлях, а не адреса); перед
    нею й після неї не стоїть літера, цифра чи `_` (`std::vector`). З кількох кінців
    береться найдовший; уже знайдену адресу не ріжемо на коротші.
    """
    out = []
    for tok in V6_TOKEN.finditer(line):
        text, t0 = tok.group(0), tok.start()
        if text.count(":") < 2:
            continue
        starts = [0] + [k + 1 for k, c in enumerate(text) if c == ":"]
        covered = 0
        for s in starts:
            if s < covered or (t0 + s > 0 and word_char(line[t0 + s - 1])):
                continue
            if s >= 2 and text[s - 2 : s] == "::":
                continue
            for end in range(len(text), s + 1, -1):
                if t0 + end < len(line) and word_char(line[t0 + end]):
                    continue
                cand = text[s:end]
                if cand.count(":") < 2:
                    break
                # Голе `::` у прозі — позначка стиснення, а не адреса; `::1` — адреса.
                if not re.search(r"[0-9A-Fa-f]", cand):
                    continue
                addr = parse_ip(cand)
                if addr is not None and addr.version == 6:
                    out.append((cand, addr))
                    covered = end
                    break
    return out


def normalize(line):
    # Markdown-екранування (`10\.0\.0\.1`, `secret\-origin`) і дефанг (`10[.]0[.]0[.]1`)
    # не міняють адреси.
    return line.replace("\\.", ".").replace("\\-", "-").replace("\\_", "_").replace("[.]", ".")


def forms(addr):
    """Сама адреса і IPv4, вбудована в IPv6: mapped, 6to4, NAT64, IPv4-compatible.
    Відома IPv4 у будь-якому з цих записів — усе одно відома і не друкується."""
    out = {addr}
    if addr.version == 6:
        for v4 in (addr.ipv4_mapped, addr.sixtofour):
            if v4 is not None:
                out.add(v4)
        if addr in NAT64 or (addr in V4_COMPAT and int(addr) > 1):
            out.add(ipaddress.IPv4Address(int(addr) & 0xFFFFFFFF))
    return out


def doc_range(addr):
    for rfc, nets in DOC_NETS.items():
        if any(addr in n for n in nets):
            return rfc
    return None


# Файл відомої адреси. Без нього правило 1 не діє — і це не «чисто», а «не
# перевірено» (вихід 3): перевірка, що мовчки пропускає без конфігурації, — та сама
# вада, що в перевірки поза git до 2026-09-30. Свідомо вимкнути правило можна лише
# явно: LEAK_ORIGIN_FILE=none. Шлях не друкуємо: у змінній помилково може стояти
# сама адреса; причину помилки теж — у ній шлях.
known, known_ips, rule1 = [], set(), "ok"
if known_path == "none":
    rule1 = "off"
    print("check-leak: попередження — правило 1 вимкнено (LEAK_ORIGIN_FILE=none)", file=sys.stderr)
else:
    try:
        # utf-8-sig — щоб BOM (Notepad) не з'їв перший рядок.
        with open(known_path, encoding="utf-8-sig") as fh:
            known = [ln.strip() for ln in fh if ln.strip()]
    except (OSError, UnicodeError):
        known = []
    if not known:
        rule1 = "unusable"
        print("check-leak: файл відомої адреси недоступний (немає, не читається або порожній) — правило 1 не перевірено", file=sys.stderr)
    for k in known:
        # Адреси беремо й з «прикрашених» рядків: `203.0.113.77 # origin`,
        # `deploy@198.51.100.9:22`, `192.0.2.44/32`.
        nk = normalize(k)
        for _, a in find_ipv4(nk) + find_ipv6(nk):
            known_ips |= forms(a)
        a = parse_ip(k)
        if a is not None:
            known_ips |= forms(a)
# Ім'я хоста не залежить від регістру — порівнюємо текст без регістру.
known_fold = [normalize(k).casefold() for k in known]

blocked, warned = [], []


def report(bucket, f, i, what):
    bucket.append(f"{f}:{i}: {what}")


for f in files:
    with open(f, encoding="utf-8", errors="replace") as fh:
        for i, line in enumerate(fh, 1):
            scan = normalize(line)
            hit = any(p in scan.casefold() for p in known_fold)
            found = find_ipv4(scan) + find_ipv6(scan)
            if hit or any(forms(addr) & known_ips for _, addr in found):
                # Решту адрес цього рядка теж не друкуємо: серед них може бути відома.
                report(blocked, f, i, "збіг з файлом відомої адреси (вміст не друкується)")
                continue
            for text, addr in found:
                rfc = doc_range(addr)
                if rfc:
                    warned.append(f"{f}:{i}: {text} — документаційний діапазон ({rfc}), не блок")
                elif any(addr in n for n in LOOPBACK_NETS):
                    warned.append(f"{f}:{i}: {text} — loopback, не блок")
                else:
                    report(blocked, f, i, f"IPv{addr.version} {text}")

for w in warned:
    print(f"попередження  {w}")
for b in blocked:
    print(f"БЛОК  {b}")
if blocked:
    print(f"check-leak: блок — знайдено {len(blocked)}; публікувати не можна")
    sys.exit(1)
if rule1 == "unusable":
    print("check-leak: не перевірено — без файла відомої адреси публікувати не можна")
    sys.exit(3)
print(f"check-leak: чисто (попереджень: {len(warned)})")
sys.exit(0)
PY
