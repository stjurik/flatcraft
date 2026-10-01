#!/usr/bin/env bash
# claude-usage.sh — скільки квоти Claude з'їдає робота: по днях і сесіях, з журналів
# Claude Code (рішення yurii 2026-10-01, економія квоти Claude).
#
# ЩО ЧИТАЄ. Усі *.jsonl у каталозі (рекурсивно, з журналами субагентів), лише записи
# `"type":"assistant"`, у яких є `message.usage`. Один виклик моделі Claude Code пише
# кількома рядками з тим самим `message.id` (кожен блок відповіді окремо) — рахується
# лише ПЕРШИЙ рядок кожного id. Виміряно на T470 2026-10-01: 3120 унікальних id, 6063
# повтори, з них у 14 usage відрізнявся від першого — похибка в бік недорахунку.
#
# ЩО ДРУКУЄ — ЛИШЕ ЧИСЛА. Журнали містять усе, що бачила сесія: код, вивід команд,
# секрети. Тому скрипт не друкує ні тексту повідомлень, ні шляхів, ні імен файлів —
# лише день (UTC), перші 8 символів id сесії, модель і числа:
#   звернень     — унікальних message.id;
#   сер.контекст — середнє (input + cache_read + cache_creation) на звернення;
#   output       — сума output_tokens.
# Рядок «РАЗОМ» — підсумок дня. Рядок, який не розібрався як JSON, пропускається і
# рахується в останньому рядку виводу.
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
import json, os, sys
from collections import defaultdict

root, since = sys.argv[1], sys.argv[2]
seen = set()
bad = 0
# (день, сесія, модель) -> [звернень, сума контексту, сума output]
acc = defaultdict(lambda: [0, 0, 0])

def num(u, k):
    v = u.get(k)
    return v if isinstance(v, int) and v >= 0 else 0

for dirpath, _dirs, files in os.walk(root):
    for name in sorted(files):
        if not name.endswith(".jsonl"):
            continue
        with open(os.path.join(dirpath, name), encoding="utf-8", errors="replace") as fh:
            for line in fh:
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
                if not isinstance(u, dict) or not isinstance(mid, str) or mid in seen:
                    continue
                seen.add(mid)
                ts = o.get("timestamp")
                day = ts[:10] if isinstance(ts, str) and len(ts) >= 10 else "????-??-??"
                if since and day < since:
                    continue
                sid = o.get("sessionId")
                sid = sid[:8] if isinstance(sid, str) and sid.replace("-", "").isalnum() else "?"
                model = m.get("model")
                model = model if isinstance(model, str) and model.replace("-", "").replace(".", "").replace("_", "").isalnum() else "?"
                a = acc[(day, sid, model)]
                a[0] += 1
                a[1] += num(u, "input_tokens") + num(u, "cache_read_input_tokens") + num(u, "cache_creation_input_tokens")
                a[2] += num(u, "output_tokens")

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
PY
