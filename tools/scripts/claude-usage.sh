#!/usr/bin/env bash
# claude-usage.sh — скільки квоти Claude з'їдає робота: по днях і сесіях, з журналів
# Claude Code (рішення yurii 2026-10-01, економія квоти Claude).
#
# ЩО ЧИТАЄ. Усі *.jsonl у каталозі (рекурсивно, з журналами субагентів), лише записи
# `"type":"assistant"`, у яких є `message.usage`. Один виклик моделі Claude Code пише
# кількома рядками з тим самим `message.id` (кожен блок відповіді окремо) — це ОДНЕ
# звернення; день, сесія й модель — з першого рядка id, токени — максимум по рядках
# id. Виміряно на T470 2026-10-01: з 4036 id перший рядок мав менший output, ніж
# пізніший, у 12, контекст відрізнявся у 2 — «перший рядок» недораховував.
#
# ЩО ДРУКУЄ — ЛИШЕ ЧИСЛА. Журнали містять усе, що бачила сесія: код, вивід команд,
# секрети. Тому скрипт не друкує ні тексту повідомлень, ні шляхів, ні імен файлів —
# лише день (перші 10 символів мітки часу, лише якщо це дата РРРР-ММ-ДД; Claude Code
# пише мітки в UTC з «Z»), перші 8 символів id сесії, модель (лише коротка назва з
# літер, цифр, «.-_», інакше «?») і числа:
#   звернень     — унікальних message.id;
#   сер.контекст — середнє (input + cache_read + cache_creation) на звернення;
#   output       — сума output_tokens.
# Рядок «РАЗОМ» — підсумок дня. Рядок, який не розібрався як JSON (порожні не в
# рахунок), і файл, який не відкрився, пропускаються і рахуються в останніх рядках
# виводу — без імен. Запис без дати з --since не рахується: його день невідомий.
#
# Використання:
#   bash tools/scripts/claude-usage.sh <каталог журналів> [--since РРРР-ММ-ДД]
# exit 0 — надруковано; 2 — помилка виклику (немає каталогу, дивна дата).
set -euo pipefail

usage() {
  echo "використання: $(basename "$0") <каталог журналів> [--since РРРР-ММ-ДД]" >&2
  exit 2
}
(($# == 1 || $# == 3)) || usage
DIR="$1"
SINCE=""
if (($# == 3)); then
  [[ "$2" == --since && "$3" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || usage
  SINCE="$3"
fi
[[ -d "$DIR" ]] || {
  echo "відмова: каталогу немає" >&2
  exit 2
}

exec python3 - "$DIR" "$SINCE" <<'PY'
import json, os, re, sys
from collections import defaultdict

root, since = sys.argv[1], sys.argv[2]
UNKNOWN_DAY = "????-??-??"
DAY_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")
MODEL_RE = re.compile(r"[A-Za-z0-9._-]{1,40}")
SID_RE = re.compile(r"[0-9A-Za-z-]+")
bad = 0
unreadable = 0
# message.id -> [день, сесія, модель, контекст, output]
calls = {}

def num(u, k):
    v = u.get(k)
    return v if isinstance(v, int) and v >= 0 else 0

for dirpath, _dirs, files in os.walk(root):
    for name in sorted(files):
        if not name.endswith(".jsonl"):
            continue
        try:
            fh = open(os.path.join(dirpath, name), encoding="utf-8", errors="replace")
        except OSError:
            # Traceback надрукував би шлях — лише рахуємо.
            unreadable += 1
            continue
        with fh:
            for line in fh:
                if not line.strip():
                    continue
                try:
                    o = json.loads(line)
                except ValueError:
                    bad += 1
                    continue
                if not isinstance(o, dict) or o.get("type") != "assistant":
                    continue
                m = o.get("message")
                if not isinstance(m, dict):
                    continue
                u, mid = m.get("usage"), m.get("id")
                if not isinstance(u, dict) or not isinstance(mid, str):
                    continue
                ctx = num(u, "input_tokens") + num(u, "cache_read_input_tokens") + num(u, "cache_creation_input_tokens")
                out = num(u, "output_tokens")
                if mid in calls:
                    c = calls[mid]
                    c[3], c[4] = max(c[3], ctx), max(c[4], out)
                    continue
                ts = o.get("timestamp")
                day = ts[:10] if isinstance(ts, str) and DAY_RE.fullmatch(ts[:10]) else UNKNOWN_DAY
                sid = o.get("sessionId")
                sid = sid[:8] if isinstance(sid, str) and SID_RE.fullmatch(sid) else "?"
                model = m.get("model")
                model = model if isinstance(model, str) and MODEL_RE.fullmatch(model) else "?"
                calls[mid] = [day, sid, model, ctx, out]

# (день, сесія, модель) -> [звернень, сума контексту, сума output]
acc = defaultdict(lambda: [0, 0, 0])
for day, sid, model, ctx, out in calls.values():
    if since and (day == UNKNOWN_DAY or day < since):
        continue
    a = acc[(day, sid, model)]
    a[0] += 1
    a[1] += ctx
    a[2] += out

print(f"{'день':10}  {'сесія':8}  {'модель':28}  {'звернень':>8}  {'сер.контекст':>12}  {'output':>9}")
for day in sorted({k[0] for k in acc}):
    tot = [0, 0, 0]
    for (d, sid, model), (n, ctx, out) in sorted(acc.items()):
        if d != day:
            continue
        print(f"{d:10}  {sid:8}  {model:28}  {n:8d}  {ctx // n:12d}  {out:9d}")
        tot = [tot[0] + n, tot[1] + ctx, tot[2] + out]
    print(f"{day:10}  {'РАЗОМ':8}  {'':28}  {tot[0]:8d}  {tot[1] // tot[0]:12d}  {tot[2]:9d}")
print(f"нерозібраних рядків: {bad}")
print(f"файлів, що не відкрились: {unreadable}")
PY
