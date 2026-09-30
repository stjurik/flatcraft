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
#   trust-worktree.sh check  <тека>   # 0 — довірені ВСІ кандидати; 1 — ні; 2 — конфіг недоступний
#   trust-worktree.sh add    <тека>   # ідемпотентно додає обидва кандидати (див. нижче)
#   trust-worktree.sh remove <тека>   # ідемпотентно прибирає обидва (після прогону)
#
# СТАН ВИМІРУ (2026-09-16): `agy -p` працює і тоді, коли в `trustedWorkspaces`
# немає жодного з двох кандидатів — контрольний прогін дав `PASS` без сигнатури
# браузерного логіна. Тобто **на момент виміру цей скрипт не впливає ні на що**.
# Лишений як страховка на випадок зміни поведінки CLI; резолвінг `agy` не
# виміряний, тому реєструються обидва шляхи, а не обраний навмання один.
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

# ДВА КАНДИДАТИ НА КЛЮЧ, і це свідоме рішення, а не перестраховка.
#
#   worktree     = `git rev-parse --show-toplevel` — усередині worktree це сам
#                  worktree;
#   корінь клону = батьківська тека `--git-common-dir` — для worktree це
#                  ГОЛОВНИЙ клон (без `--path-format=absolute` git віддає
#                  відносний шлях, тому прапорець обов'язковий).
#
# Чому обидва. Вимір М-1 (PR #110) показав, що **Claude Code** ключиться на
# корінь клону: запис для теки worktree не діє взагалі. Чи так само поводиться
# `agy` — **не виміряно**: контрольний прогін 2026-09-16 (виклик у вікні OQ-35)
# показав, що `agy -p` працює і тоді, коли в списку немає ЖОДНОГО з двох
# шляхів. Тобто список нічого не гейтить, і за такої конструкції питання ключа
# не має відповіді — не «відповідь негативна», а сам вимір неможливий.
#
# Тому ми не вибираємо між двома живими кандидатами і не переносимо поведінку
# Claude Code на `agy` без виміру: реєструємо обидва. Це НЕ той випадок, що
# інертні `Write(...)` у deny-списку — там половина була ВІДОМО мертвою і
# вчила хибного патерну; тут обидва записи однаково правдоподібні.
# **Коли резолвінг `agy` виміряють — лишити один.**
resolve_candidates() {
  local target="$1" wt="" root=""
  wt="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)" || wt=""
  root="$(git -C "$target" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
    && root="$(dirname "$root")" || root=""
  # Тека ще не створена (autorun.sh кличе `check` до `worktree add`) — беремо
  # шлях як є; відповідь «не довірена» тут правильна.
  [[ -n "$wt" ]] || wt="$(realpath -m "$target" 2>/dev/null || echo "$target")"
  [[ -n "$root" ]] || root="$wt"
  printf '%s\n' "$wt"
  # У звичайному клоні обидва збігаються — другий запис не потрібен.
  [[ "$root" == "$wt" ]] || printf '%s\n' "$root"
}

mapfile -t CANDIDATES < <(resolve_candidates "$TARGET")

if [[ ! -f "$SETTINGS" ]]; then
  echo "✗ немає файлу налаштувань agy: $SETTINGS" >&2
  echo "  (agy на цій машині не налаштований — це не помилка цього скрипта)" >&2
  exit 2
fi

python3 - "$SETTINGS" "$CMD" "${CANDIDATES[@]}" <<'PY'
import json, os, sys, tempfile

settings_path, cmd = sys.argv[1], sys.argv[2]
candidates = sys.argv[3:]

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

# Порівняння через realpath з обох боків: у списку трапляються симлінки й
# хвостові слеші, а рівність шляхів тут — єдине, що вирішує довіру.
targets = [os.path.realpath(c) for c in candidates]
listed = {os.path.realpath(str(e)) for e in entries}
missing = [t for t in targets if t not in listed]

if cmd == "check":
    # 0 лише якщо присутні ВСІ кандидати: `add` реєструє обидва, тож часткова
    # реєстрація — це не «довірено», а недороблена робота, і мовчати про неї
    # означало б повторити клас «виглядає захистом, але не діє».
    if missing:
        for m in missing:
            print(f"немає у списку: {m}")
    sys.exit(1 if missing else 0)

if cmd == "add":
    if not missing:
        print("= вже довірені: " + ", ".join(targets))
        sys.exit(0)
    entries.extend(missing)
    changed = missing
else:  # remove
    removed = [t for t in targets if t in listed]
    if not removed:
        print("= не було у списку: " + ", ".join(targets))
        sys.exit(0)
    entries = [e for e in entries if os.path.realpath(str(e)) not in set(targets)]
    changed = removed

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

prefix = "+ довірена: " if cmd == "add" else "- знято довіру: "
for path in changed:
    print(prefix + path)
PY
