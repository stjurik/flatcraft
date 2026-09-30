#!/usr/bin/env bash
# check-deny-parity.sh — не дає розійтись двом спискам deny-правил.
#
# ЧОМУ ЦЕ ІСНУЄ. Механічна заборона запису живе у ДВОХ місцях:
#   1. .github/workflows/ai-fix.yml — inline `settings:` для Будівельника в CI;
#   2. .claude/settings.autonomous.json — трекований файл для headless-прогонів
#      (autorun.sh) і майбутніх прогонів на A8.
# Списки дублюються, бо дія claude-code-action споживає inline-JSON, а CLI —
# файл. Дубль без перевірки = гарантоване розходження: docs/16 §1 описує рівно
# цей клас помилки («розділ показував JSON як чинний механізм; він ним ніколи
# не був»). Тому інваріант перевіряється, а не декларується.
#
# ІНВАРІАНТ: кожне правило з ai-fix.yml МУСИТЬ бути у трекованому файлі.
# Зворотне не вимагається — трекований файл може бути суворішим (напр. він
# додає bend-machine-esi.yaml за ADR-040 §1, якого в ai-fix.yml ще немає).
#
# Використання: tools/scripts/check-deny-parity.sh [workflow.yml] [settings.json]
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
WORKFLOW="${1:-$REPO_ROOT/.github/workflows/ai-fix.yml}"
SETTINGS="${2:-$REPO_ROOT/.claude/settings.autonomous.json}"

python3 - "$WORKFLOW" "$SETTINGS" <<'PY'
import json, re, sys

workflow_path, settings_path = sys.argv[1], sys.argv[2]

with open(workflow_path, encoding="utf-8") as fh:
    lines = fh.readlines()

# Витягуємо блок `settings: |` — беремо рядки, відступ яких більший за відступ
# самого ключа, і знімаємо цей відступ, як це робить YAML для literal-блоку.
block, indent = [], None
for line in lines:
    if indent is None:
        m = re.match(r"^(\s*)settings:\s*\|\s*$", line)
        if m:
            indent = len(m.group(1))
        continue
    if line.strip() and (len(line) - len(line.lstrip())) <= indent:
        break
    block.append(line[indent:] if len(line) > indent else "\n")

if indent is None:
    sys.exit(f"::error::у {workflow_path} немає блоку `settings: |` — deny-правила зникли?")

try:
    wf_deny = set(json.loads("".join(block))["permissions"]["deny"])
except (ValueError, KeyError) as exc:
    sys.exit(f"::error::не розібрав settings-блок у {workflow_path}: {exc}")

with open(settings_path, encoding="utf-8") as fh:
    tracked_deny = set(json.load(fh)["permissions"]["deny"])

missing = sorted(wf_deny - tracked_deny)
if missing:
    print(
        "::error::deny-правила розійшлись: є в ai-fix.yml, немає у трекованому файлі: "
        + ", ".join(missing),
        file=sys.stderr,
    )
    for rule in missing:
        print(f"  ✗ {rule}", file=sys.stderr)
    sys.exit(1)

extra = sorted(tracked_deny - wf_deny)
print(f"OK: {len(wf_deny)} правил ai-fix.yml присутні у трекованому файлі.")
if extra:
    print(f"     (трекований файл суворіший на {len(extra)}: {', '.join(extra)})")
PY
