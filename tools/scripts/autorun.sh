#!/usr/bin/env bash
# autorun.sh — headless-запуск промпту з docs/promts/autorun/ у власному git worktree.
# Див. docs/16_AUTONOMOUS_RUNS.md.
#
# Використання:
#   tools/scripts/autorun.sh <prompt_id> <branch> [model]
#   tools/scripts/autorun.sh a1 docs/phase-3-3-observability opus
#   tools/scripts/autorun.sh b1 feat/observability-events sonnet
set -euo pipefail

PROMPT_ID="${1:?вкажи prompt id, напр. a1}"
BRANCH="${2:?вкажи git-гілку, напр. docs/phase-3-3-observability}"
MODEL="${3:-sonnet}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
PROMPT_FILE="$REPO_ROOT/docs/promts/autorun/${PROMPT_ID}.md"
HEADER_FILE="$REPO_ROOT/docs/promts/autorun/_autonomous-header.md"
WT_ROOT="${AUTORUN_WT_ROOT:-$HOME/hart-wt}"
LOG_ROOT="${AUTORUN_LOG_ROOT:-$HOME/hart-logs}"
WT_DIR="$WT_ROOT/$PROMPT_ID"
LOG_FILE="$LOG_ROOT/${PROMPT_ID}-$(date +%Y%m%d-%H%M%S).jsonl"

[[ -f "$PROMPT_FILE" ]] || { echo "✗ нема $PROMPT_FILE (розклади промпти з docs/15 по файлах)"; exit 1; }
[[ -f "$HEADER_FILE" ]] || { echo "✗ нема $HEADER_FILE (див. docs/16 §3)"; exit 1; }
mkdir -p "$WT_ROOT" "$LOG_ROOT"

echo "── worktree: $WT_DIR (гілка $BRANCH зі свіжого origin/main)"
git -C "$REPO_ROOT" fetch origin main
if [[ ! -d "$WT_DIR" ]]; then
  git -C "$REPO_ROOT" worktree add "$WT_DIR" -b "$BRANCH" origin/main
fi

# Реєстрація worktree у `trustedWorkspaces` — СТРАХОВКА, не передумова. Чи
# впливає цей список на `agy -p`, не вирішено: виміри 2026-09-14 і 2026-09-15
# суперечать одне одному (docs/19 §D.4). Тому крок нічого не блокує і не
# перериває прогін — але якщо довіра таки має значення, він знімає найдорожчий
# симптом: недовірена тека просить браузерний OAuth, тобто виглядає як
# протермінований логін, і діагностика йде не туди. Довіру НЕ знімаємо в кінці:
# worktree живе далі, і рев'ю в ньому теж (`remove` — для прибирання теки).
echo "── довіра agy до worktree (docs/19 §D.4)"
TRUST_CODE=0
"$REPO_ROOT/tools/scripts/trust-worktree.sh" add "$WT_DIR" || TRUST_CODE=$?
case "$TRUST_CODE" in
  0) ;;
  # Не фатально: задача прогону — Claude-run, `agy` тут другий пул для рев'ю.
  # Зупиняти роботу через ненастроєний Gemini було б гірше, ніж прогін без нього.
  2) echo "   ⚠ agy на цій машині не налаштований — прогін без Gemini-пулу (ADR-039 §5)" ;;
  *) echo "   ⚠ реєстрація не вдалась (код $TRUST_CODE) — agy у цій теці впаде у браузерний OAuth" ;;
esac

echo "── залежності (node_modules/venv не шаруться між worktree)"
(cd "$WT_DIR" && pnpm install --frozen-lockfile)
(cd "$WT_DIR/workers/cad" && uv sync)

echo "── headless-прогін: model=$MODEL, лог: $LOG_FILE"
cd "$WT_DIR"
# --settings: механічні deny-правила з трекованого файлу (docs/16 §1). Без нього
# локальний headless-прогін не має ЖОДНОГО обмеження — правило, якого немає в git,
# не захищає ні інший клон, ні прогін на A8 (docs/19 §7 п.4).
cat "$HEADER_FILE" "$PROMPT_FILE" | claude -p \
  --model "$MODEL" \
  --settings "$WT_DIR/.claude/settings.autonomous.json" \
  --permission-mode acceptEdits \
  --allowedTools "Read,Glob,Grep,Edit,Write,Bash(git:*),Bash(gh pr create:*),Bash(gh pr view:*),Bash(pnpm:*),Bash(uv:*)" \
  --max-turns 200 \
  --output-format stream-json --verbose \
  | tee "$LOG_FILE"

echo ""
echo "── ГОТОВО. Приймання (docs/16 §7):"
echo "   cd $WT_DIR && git log --oneline origin/main.."
echo "   gh pr list --draft"
echo "   лог прогону: $LOG_FILE"
