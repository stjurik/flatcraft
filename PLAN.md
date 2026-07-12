# WP1 — Autorun-тулінг (docs/autonomous-runs)

Package 1 з master-run'у (`docs/promts/master-softlaunch-run.md`).

## Мета

Внести у git інфраструктуру для автономних headless-прогонів промптів з `docs/15_LLM_PROMPTS.md`. Все untracked, лежить у робочому дереві з ~2026-07-05 — треба закомітити, з невеликим прибиранням.

## Deliverables

| #   | Дія    | Файл                                                                                                                       |
| --- | ------ | -------------------------------------------------------------------------------------------------------------------------- |
| 1   | ADD    | `docs/16_AUTONOMOUS_RUNS.md` — специфікація автономних прогонів (13 KB)                                                    |
| 2   | ADD    | `docs/promts/autorun/_autonomous-header.md` — хедер, що модифікує промпти під headless                                     |
| 3   | ADD    | `tools/scripts/autorun.sh` — runner (worktree + `claude -p` + логування)                                                   |
| 4   | ADD    | `docs/promts/phase-3-3-b-activation.md` — промпт для активації Phase 3.3-B (використовується у WP2)                        |
| 5   | ADD    | `docs/promts/master-softlaunch-run.md` — цей master-run (для аудиту)                                                       |
| 6   | ADD    | `.claude/settings.json` — allowlist + **новий deny-блок** із docs/16 §1.3 (mech-guard інваріантів CLAUDE.md §6)            |
| 7   | DELETE | `.github/workflows/ai-cloud-developer.yml` — порожній stub, слід ранніх експериментів                                      |
| 8   | ADD    | `PLAN.md` — цей файл (буде видалений у фінальному PR-cleanup або лишений як artefact — залежить від конвенції, поки лишаю) |

## Deny-правила, які додаються у `.claude/settings.json`

З `docs/16_AUTONOMOUS_RUNS.md §1.3` (mech-guard інваріантів CLAUDE.md §6):

```json
"deny": [
  "Edit(packages/db/migrations/**)",
  "Edit(infra/**)",
  "Edit(CLAUDE.md)",
  "Bash(pnpm discord:apply:*)",
  "Bash(git push --force:*)",
  "Bash(docker:*)"
]
```

## Тести

- `pnpm lint` (workspace root) — усі markdown/yaml/json проходять prettier.
- `git status` після commit — чистий (untracked-payload зник).

## Обмеження (з master-run §режим-автономії)

- Гілка від `origin/main`, не стакати.
- Draft PR у фіналі, **НЕ merge**.
- Conventional Commits, без force-push.

## Питання до yurii (для PR review)

_(зафіксовано у PR description, не блокують roll-out)_
