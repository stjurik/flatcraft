#!/usr/bin/env bash
# trust-worktree.sh — реєструє корінь git-worktree у `trustedWorkspaces` (`agy`).
#
# ЧОМУ ЦЕ ІСНУЄ — і чого воно НЕ доводить. ADR-039 §2 будує ізоляцію на
# «власному worktree на задачу», а §5 — на Gemini як другому квотному пулі.
# Два виміри дають протилежні відповіді на те, чи ці вимоги сумісні:
#
#   2026-09-14: trustedWorkspaces = [~/hart-wt], cwd = ~/hart-wt/a8-stage-0
#               → браузерний OAuth (тобто довіра НЕ успадковується від батька)
#   2026-09-15: trustedWorkspaces = [~/lun_monitor] (ні теки, ні батька),
#               cwd = ~/hart-wt/architectural-dead-end
#               → exit 0, `read_file`+`write_file` виконано, nonce дослівно,
#                 0 входжень `soft-denying` (тобто список не гейтить `-p` ВЗАГАЛІ)
#
# Суперечність НЕ закрита: другий вимір не об'єднується з першим, і причина
# першого невідома. Обидві точки — у `docs/19` §D.4, без «переможця».
# Окремо з'ясовано, що вердикт 7 у PR #108 давав НАШ гейт у
# `check-agy-headless.sh` (точний збіг шляху), а не `agy` — його знято.
#
# Тому цей скрипт — страховка, а не лікування: він нічого не блокує і нікого не
# лікує від проблеми, існування якої не підтверджене. Його цінність у тому, що
# якщо довіра колись таки має значення, недовірена тека просить браузерний
# OAuth — тобто виглядає як протермінований логін, і година діагностики йде не
# туди. `check` відповідає на це за 0 викликів Gemini і за мілісекунди.
#
# Використання:
#   trust-worktree.sh check  <тека>   # 0 — довірена; 1 — ні; 2 — конфіг недоступний
#   trust-worktree.sh add    <тека>   # ідемпотентно додає корінь git цієї теки
#   trust-worktree.sh remove <тека>   # ідемпотентно прибирає (після прогону)
#
# Конфіг: $AGY_SETTINGS або ~/.gemini/antigravity-cli/settings.json.
# Файл НЕ створюється, якщо його немає: відсутній конфіг означає, що `agy` на цій
# машині не налаштований, і мовчазна підміна цього факту порожнім файлом сховала б
# справжню причину (`docs/16` §1 — декларація замість механізму).
set -uo pipefail

CMD="${1:-}"
TARGET="${2:-}"
SETTINGS="${AGY_SETTINGS:-$HOME/.gemini/antigravity-cli/settings.json}"

usage() {
  echo "використання: $(basename "$0") {check|add|remove} <тека>" >&2
  exit 2
}

[[ -n "$CMD" && -n "$TARGET" ]] || usage
case "$CMD" in check | add | remove) ;; *) usage ;; esac

# Ключ реєстрації — КОРІНЬ git, а не передана тека: `agy` звіряє саме корінь
# (`git rev-parse --show-toplevel`), і запис підтеки лишив би теку недовіреною.
# Для ще не створеної теки (autorun.sh кличе `check` до `worktree add`) корінь
# невідомий — беремо шлях як є, відповідь «не довірена» тут правильна.
ROOT="$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null)" || ROOT=""
if [[ -z "$ROOT" ]]; then
  ROOT="$(realpath -m "$TARGET" 2>/dev/null || echo "$TARGET")"
fi

if [[ ! -f "$SETTINGS" ]]; then
  echo "✗ немає файлу налаштувань agy: $SETTINGS" >&2
  echo "  (agy на цій машині не налаштований — це не помилка цього скрипта)" >&2
  exit 2
fi

python3 - "$SETTINGS" "$ROOT" "$CMD" <<'PY'
import json, os, sys, tempfile

settings_path, root, cmd = sys.argv[1], sys.argv[2], sys.argv[3]

try:
    with open(settings_path, encoding="utf-8") as fh:
        data = json.load(fh)
except (OSError, ValueError) as exc:
    print(f"✗ не читається {settings_path}: {exc}", file=sys.stderr)
    sys.exit(2)

if not isinstance(data, dict):
    print(f"✗ {settings_path}: очікував об'єкт JSON", file=sys.stderr)
    sys.exit(2)

entries = data.get("trustedWorkspaces")
if entries is None:
    entries = []
elif not isinstance(entries, list):
    print(f"✗ {settings_path}: trustedWorkspaces не список", file=sys.stderr)
    sys.exit(2)

target = os.path.realpath(root)
# Порівняння через realpath з обох боків: у списку трапляються симлінки й
# хвостові слеші, а рівність шляхів тут — єдине, що вирішує довіру.
present = any(os.path.realpath(str(e)) == target for e in entries)

if cmd == "check":
    sys.exit(0 if present else 1)

if cmd == "add":
    if present:
        print(f"= вже довірена: {target}")
        sys.exit(0)
    entries.append(target)
else:  # remove
    if not present:
        print(f"= не було у списку: {target}")
        sys.exit(0)
    entries = [e for e in entries if os.path.realpath(str(e)) != target]

data["trustedWorkspaces"] = entries

# Запис через тимчасовий файл у тій самій теці + os.replace: конфіг `agy` читає
# сторонній процес, і обірваний запис лишив би його без trustedWorkspaces взагалі.
directory = os.path.dirname(settings_path) or "."
fd, tmp = tempfile.mkstemp(dir=directory, prefix=".trust-worktree-")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    os.replace(tmp, settings_path)
except BaseException:
    os.path.exists(tmp) and os.unlink(tmp)
    raise

print(("+ довірена: " if cmd == "add" else "- знято довіру: ") + target)
PY
