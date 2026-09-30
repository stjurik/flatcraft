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
IPV4 = re.compile(r"(?<!\d)(?<!\d\.)(?:\d{1,3}\.){3}\d{1,3}(?!\d)(?!\.\d)")
# Кандидат IPv6 не може бути частиною слова: так std::vector і Foo::Bar — не адреси.
# Валідність (14:31:15 — час, а не адреса) перевіряє ipaddress нижче.
IPV6 = re.compile(r"(?<![0-9A-Za-z:])(?:[0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4}(?![0-9A-Za-z:])")

known = []
if os.path.isfile(known_path):
    with open(known_path, encoding="utf-8") as fh:
        # Порожній шаблон збігся б з кожним рядком — відкидаємо.
        known = [ln.strip() for ln in fh if ln.strip()]
else:
    print(f"check-leak: попередження — файла відомої адреси немає ({known_path}), правило 1 не діє", file=sys.stderr)

blocked, warned = [], []


def report(bucket, f, i, what):
    bucket.append(f"{f}:{i}: {what}")


def doc_range(addr):
    for rfc, nets in DOC_NETS.items():
        if any(addr in n for n in nets):
            return rfc
    return None


for f in files:
    with open(f, encoding="utf-8", errors="replace") as fh:
        for i, line in enumerate(fh, 1):
            hit = any(p in line for p in known)
            if hit:
                # Решту адрес цього рядка теж не друкуємо: серед них може бути відома.
                report(blocked, f, i, "збіг з файлом відомої адреси (вміст не друкується)")
                continue
            found = [m.group(0) for m in IPV4.finditer(line)]
            for m in IPV6.finditer(line):
                found.append(m.group(0))
            for text in found:
                try:
                    addr = ipaddress.ip_address(text)
                except ValueError:
                    continue
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
