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
#   2. Будь-яка інша IPv4 чи IPv6 адреса, зокрема loopback і приватні, — БЛОК.
#   3. Документаційні діапазони — ПОПЕРЕДЖЕННЯ, не блок: RFC 5737 (192.0.2.0/24,
#      198.51.100.0/24, 203.0.113.0/24) і RFC 3849 (2001:db8::/32). Їх пишуть у
#      прикладах навмисно.
#
# ЧОГО НЕ ДОВОДИТЬ. Шукає адреси й рядки відомого файла, а не секрети взагалі
# (токени, ключі) і не імена машин. Без файла відомої адреси правило 1 не діє —
# про це друкується попередження. Рядок на кшталт версії з чотирьох чисел
# (1.2.3.4) — теж «адреса»: помилка в бік блоку.
#
# Використання: tools/scripts/check-leak.sh <файл>...
#   LEAK_ORIGIN_FILE — файл відомої адреси, по одному шаблону в рядку
#                      (дефолт ~/.flatcraft/leak/origin-host).
# Вихід: 0 — чисто (попередження можливі); 1 — блок; 2 — помилка виклику.
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
import os
import re
import sys

known_path, files = sys.argv[1], sys.argv[2:]

DOC_NETS = {
    "RFC 5737": [ipaddress.ip_network(n) for n in ("192.0.2.0/24", "198.51.100.0/24", "203.0.113.0/24")],
    "RFC 3849": [ipaddress.ip_network(n) for n in ("2001:db8::/32",)],
}
# Межі — не цифра й не «цифра.» перед, не цифра й не «.цифра» після: так крапка в
# кінці речення не ховає адресу, а версія 2.1.272 не стає нею.
IPV4 = re.compile(r"(?<![0-9])(?<![0-9]\.)(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![0-9])(?!\.[0-9])")
# Кандидат IPv6 — будь-яка послідовність hex-цифр, двокрапок і крапок щонайменше з
# двома двокрапками. Далі find_ipv6 шукає в ній адресу; регулярний вираз з межами
# (перша версія) пропускав `server:2a01:…` і адреси з 8 двокрапками — рецензія #170.
V6_TOKEN = re.compile(r"[0-9A-Fa-f:.]+")


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


def find_ipv6(line):
    """(текст, адреса) для кожної IPv6 у рядку.

    Адреса починається на початку кандидата або одразу після його двокрапки (так
    `server:2a01:…` дає `2a01:…`), і перед нею та після неї не стоїть літера чи
    цифра — тож `d::` у `std::vector` не адреса. З кількох кінців береться
    найдовший; уже знайдену адресу не ріжемо на коротші.
    """
    out = []
    for tok in V6_TOKEN.finditer(line):
        text, t0 = tok.group(0), tok.start()
        if text.count(":") < 2:
            continue
        starts = [0] + [k + 1 for k, c in enumerate(text) if c == ":"]
        covered = 0
        for s in starts:
            if s < covered or (t0 + s > 0 and line[t0 + s - 1].isalnum()):
                continue
            for end in range(len(text), s + 1, -1):
                if t0 + end < len(line) and line[t0 + end].isalnum():
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


def doc_range(addr):
    for rfc, nets in DOC_NETS.items():
        if any(addr in n for n in nets):
            return rfc
    return None


known = []
if os.path.isfile(known_path):
    with open(known_path, encoding="utf-8") as fh:
        # Порожній шаблон збігся б з кожним рядком — відкидаємо.
        known = [ln.strip() for ln in fh if ln.strip()]
else:
    # Шлях не друкуємо: у LEAK_ORIGIN_FILE помилково може стояти сама адреса.
    print("check-leak: попередження — файла відомої адреси немає, правило 1 не діє", file=sys.stderr)
# Ім'я хоста не залежить від регістру, а одна IPv6 має кілька записів — тому
# порівнюємо і текст без регістру, і самі адреси.
known_fold = [k.casefold() for k in known]
known_ips = {a for a in (parse_ip(k) for k in known) if a is not None}

blocked, warned = [], []


def report(bucket, f, i, what):
    bucket.append(f"{f}:{i}: {what}")


def is_known(addr):
    mapped = getattr(addr, "ipv4_mapped", None)
    return addr in known_ips or (mapped is not None and mapped in known_ips)


for f in files:
    with open(f, encoding="utf-8", errors="replace") as fh:
        for i, line in enumerate(fh, 1):
            # `10\.0\.0\.1` — markdown-екранування крапок; адреса та сама.
            scan = line.replace("\\.", ".")
            hit = any(p in scan.casefold() for p in known_fold)
            found = []
            for m in IPV4.finditer(scan):
                addr = parse_ip(m.group(0))
                if addr is not None:
                    found.append((m.group(0), addr))
            found += find_ipv6(scan)
            if hit or any(is_known(addr) for _, addr in found):
                # Решту адрес цього рядка теж не друкуємо: серед них може бути відома.
                report(blocked, f, i, "збіг з файлом відомої адреси (вміст не друкується)")
                continue
            for text, addr in found:
                rfc = doc_range(addr)
                if rfc:
                    warned.append(f"{f}:{i}: {text} — документаційний діапазон ({rfc}), не блок")
                else:
                    report(blocked, f, i, f"IPv{addr.version} {text}")

for w in warned:
    print(f"попередження  {w}")
for b in blocked:
    print(f"БЛОК  {b}")
if blocked:
    print(f"check-leak: блок — знайдено {len(blocked)}; публікувати не можна")
else:
    print(f"check-leak: чисто (попереджень: {len(warned)})")
sys.exit(1 if blocked else 0)
PY
