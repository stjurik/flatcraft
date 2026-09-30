#!/usr/bin/env bash
# measure-trust.sh — вимір М-1: чи успадковує worktree довіру Claude Code
# і чи механічний запис `hasTrustDialogAccepted` рівносильний діалогу.
#
# ЧОМУ ЦЕ СКРИПТ, А НЕ КОМАНДИ У ЗВІТІ. Обидві відповіді — властивість
# КОНКРЕТНОЇ версії CLI (виміряно на 2.1.272). Будь-яке оновлення Claude Code
# їх знецінює, а переміряти треба буде за секунди, не перенабираючи руками.
#
# ЧОМУ ТУТ ТРИ ВЕРДИКТИ, А НЕ ДВА. `docs/16` §1 і §2.3 промпту Стадії 1:
# ненульовий код виходу означає «виміру НЕ БУЛО», а не «ні». Прецедент, що
# коштував хибного висновку: `exit=1` разом із рядком
# `--dangerously-skip-permissions cannot be used with root/sudo privileges`
# зарахували як «deny спрацював», хоча виклику просто не сталося. Тому
# відмова інструмента тут — окремий код 2, а не «недовірена».
#
# Вердикти `probe`:
#   0 — ✅ TRUSTED: рядка `Ignoring N permissions.allow entries` немає, CLI відповів;
#   1 — ⚠️  UNTRUSTED: рядок є, allow-список відкинуто (N друкується);
#   2 — ❓ NOT-MEASURED: CLI не відповів (відмова, порожній вивід, таймаут).
#
# Використання:
#   measure-trust.sh probe <тека> [--timeout СЕК]   # прогін і класифікація
#   measure-trust.sh show  <тека>                   # стан флага для теки
#   measure-trust.sh set   <тека>                   # атомарно вписати true
#   measure-trust.sh unset <тека>                   # прибрати запис
#
# Конфіг: $CLAUDE_CONFIG або ~/.claude.json. Файл НЕ створюється, якщо його
# немає: відсутній конфіг означає, що Claude Code тут не запускався, і мовчазна
# підміна цього факту порожнім файлом сховала б справжню причину.
#
# `set`/`unset` існують РІВНО для прогонів C і D виміру М-1 (дозвіл оркестратора
# 2026-09-15: копія до, відновлення після, атомарна правка, одноразові теки).
# Це НЕ реалізація OQ-22(б) — там потрібен крок у демоні й роль Ansible.
set -uo pipefail

CMD="${1:-}"
TARGET="${2:-}"
shift 2 2>/dev/null || true
TIMEOUT=120
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout) TIMEOUT="${2:-120}"; shift 2 ;;
    *) shift ;;
  esac
done

CONFIG="${CLAUDE_CONFIG:-$HOME/.claude.json}"

usage() {
  echo "використання: $(basename "$0") {probe|show|set|unset} <тека> [--timeout СЕК]" >&2
  exit 2
}
[[ -n "$CMD" && -n "$TARGET" ]] || usage
case "$CMD" in probe | show | set | unset) ;; *) usage ;; esac

# Ключ довіри в ~/.claude.json — АБСОЛЮТНИЙ шлях теки (з тексту самої помилки
# CLI: `projects["/home/agent/hart"]`). Тому нормалізуємо через realpath: запис
# із хвостовим слешем або через симлінк дав би інший ключ і тихо не спрацював.
ABS="$(realpath -m "$TARGET" 2>/dev/null || echo "$TARGET")"

# ── Робота з конфігом (show/set/unset) ─────────────────────────────────────
config_op() {
  local op="$1"
  if [[ ! -f "$CONFIG" ]]; then
    echo "✗ немає файлу конфігу: $CONFIG" >&2
    echo "  (Claude Code тут не запускався — це не помилка цього скрипта)" >&2
    return 2
  fi
  python3 - "$CONFIG" "$ABS" "$op" <<'PY'
import json, os, sys, tempfile

path, target, op = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
except (OSError, ValueError) as exc:
    print(f"✗ не читається {path}: {exc}", file=sys.stderr)
    sys.exit(2)
if not isinstance(data, dict):
    print(f"✗ {path}: очікував об'єкт JSON", file=sys.stderr)
    sys.exit(2)

projects = data.get("projects")
if projects is None:
    projects = {}
elif not isinstance(projects, dict):
    print(f"✗ {path}: projects не об'єкт", file=sys.stderr)
    sys.exit(2)

entry = projects.get(target)
current = entry.get("hasTrustDialogAccepted") if isinstance(entry, dict) else None

if op == "show":
    print(f"{target}: hasTrustDialogAccepted={current!r}")
    sys.exit(0 if current is True else 1)

if op == "set":
    if current is True:
        print(f"= вже довірена: {target}")
        sys.exit(0)
    # Інші поля запису НЕ чіпаємо: у projects[...] живуть історія, allowedTools
    # та інші ключі CLI, і затирання їх зробило б вимір деструктивним.
    if not isinstance(entry, dict):
        entry = {}
    entry["hasTrustDialogAccepted"] = True
    projects[target] = entry
else:  # unset
    if not isinstance(entry, dict) or current is None:
        print(f"= запису не було: {target}")
        sys.exit(0)
    entry.pop("hasTrustDialogAccepted", None)
    # Порожній запис прибираємо цілком — інакше `show` не відрізнить
    # «ніколи не було» від «прибрали», а це різні базові лінії для прогону B.
    if entry:
        projects[target] = entry
    else:
        projects.pop(target, None)

data["projects"] = projects

# Бекап ДО правки: у цьому файлі живе історія проєктів, і зіпсувати його
# означало б зламати робочу конфігурацію заради виміру.
backup = f"{path}.measure-bak"
if not os.path.exists(backup):
    with open(backup, "w", encoding="utf-8") as fh:
        json.dump(json.load(open(path, encoding="utf-8")), fh, ensure_ascii=False, indent=2)

# Атомарний запис: CLI читає цей файл паралельно, і обірваний запис лишив би
# його без projects взагалі.
directory = os.path.dirname(path) or "."
fd, tmp = tempfile.mkstemp(dir=directory, prefix=".measure-trust-")
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    os.replace(tmp, path)
except BaseException:
    os.path.exists(tmp) and os.unlink(tmp)
    raise

print(("+ довірена: " if op == "set" else "- знято довіру: ") + target)
PY
}

case "$CMD" in
  show | set | unset)
    config_op "$CMD"
    exit $?
    ;;
esac

# ── probe ──────────────────────────────────────────────────────────────────
[[ -d "$ABS" ]] || { echo "✗ немає теки: $ABS" >&2; exit 2; }
command -v claude >/dev/null 2>&1 || { echo "✗ немає claude у PATH" >&2; exit 2; }
command -v timeout >/dev/null 2>&1 || { echo "✗ немає timeout" >&2; exit 2; }

NONCE="TRUST-PROBE-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
OUT="$(mktemp -t measure-trust-XXXXXX.txt)"
trap 'rm -f "$OUT"' EXIT

claude_exit=0
(cd "$ABS" && timeout "$TIMEOUT" claude -p "Відповідай РІВНО одним словом: $NONCE") \
  >"$OUT" 2>&1 || claude_exit=$?

echo "── М-1 probe: $ABS (таймаут ${TIMEOUT}с)"
echo "   nonce: $NONCE | exit claude: $claude_exit"

IGNORING="$(grep -oE 'Ignoring [0-9]+ permissions\.allow entries' "$OUT" | head -1)"
N="$(sed -n 's/.*Ignoring \([0-9]\+\) permissions\.allow entries.*/\1/p' "$OUT" | head -1)"

# §2.3: спершу відсіюємо «виміру не було», і ЛИШЕ потім класифікуємо довіру.
# Порядок важливий: відмова CLI теж не містить рядка Ignoring, тобто без цієї
# гілки вона зарахувалась би як TRUSTED — найдорожча з можливих помилок тут.
if ! grep -qF -- "$NONCE" "$OUT"; then
  echo "── Вердикт М-1: ❓ NOT-MEASURED — CLI не повернув nonce"
  echo "   (ненульовий код, відмова інструмента, порожній вивід або таймаут"
  echo "    означають «невідомо», а не «недовірена» — §2.3)"
  echo "   ── дослівний вивід ──"
  sed 's/^/   /' "$OUT"
  exit 2
fi

if [[ -n "$IGNORING" ]]; then
  echo "── Вердикт М-1: ⚠️  UNTRUSTED — allow-список відкинуто"
  echo "   дослівно: $IGNORING"
  echo "   N=$N"
  exit 1
fi

echo "── Вердикт М-1: ✅ TRUSTED — рядка Ignoring немає, nonce повернувся"
exit 0
