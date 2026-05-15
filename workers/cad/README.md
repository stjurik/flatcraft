# flatcraft-cad — Python CAD Worker

> Слухає Redis-чергу (BullMQ), генерує DXF/PDF/STEP. CLI режим — для розробки і ручних тестів.

## Setup

```bash
cd workers/cad
uv sync                      # створює .venv і ставить залежності
```

## Команди

```bash
uv run pytest                # тести (snapshot DXF + unit)
uv run mypy .                # type-check
uv run ruff check .          # lint
uv run ruff format .         # format

# Listen-mode (продакшн)
uv run python -m flatcraft_cad.worker

# CLI (для розробки)
uv run python -m flatcraft_cad.cli render \
    --template l_bracket \
    --params @samples/l_bracket_100x150x2.json \
    --formats dxf,pdf,step \
    --out ./out/

# Перевірити детермінізм
../../tools/scripts/check-cad-determinism.sh
```

## Вхідні дані

Worker читає `bend-machine-esi.yaml` з `../../packages/cad-engine/data/`. Ніколи не дублюємо machine-spec — це єдине джерело істини.

Параметри шаблону приходять у JSON-payload, який валідується через Pydantic-моделі (генеруються з Zod через JSON Schema).

## Тести

- `tests/snapshots/` — фіксовані DXF/PDF байти, які не змінюються між запусками. Якщо тест падає — або (а) ви свідомо змінили геометрію, тоді оновіть snapshot, або (б) детермінізм зламаний → треба фіксити.
- `tests/unit/` — perевірки валідаторів, K-фактору, формул розгортки.
- `tests/integration/` — повний цикл worker.start → отримання job → обробка → перевірка R2 mock.
