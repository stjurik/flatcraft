#!/usr/bin/env bash
# check-hook-loud.test.sh — доказ, що тихий pre-commit стає гучною відмовою.
#
# Фікстури розводять те, що скрипт розрізняє (docs/16 §8.1):
#   * PATH і node_modules кореня — два різні способи знайти lefthook;
#   * поточна тека і корінь репо — хук шукає від кореня, не від cwd;
#   * «файл є» і «файл запускається».
# Мутації в кінці: зламана перевірка мусить зробити набір червоним.
#
# Запуск: tools/scripts/check-hook-loud.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${HOOK_LOUD_UNDER_TEST:-$HERE/check-hook-loud.sh}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
ok() { [[ -z "${QUIET:-}" ]] && echo "✓ $1"; return 0; }
bad() {
  echo "✗ $1"
  fail=1
}

# Мінімальний PATH без будь-якого справжнього lefthook.
BASE_PATH="/usr/bin:/bin"
arch="$(uname -m | sed 's/aarch64/arm64/;s/x86_64/x64/')"
os="$(uname | tr '[:upper:]' '[:lower:]')"

newrepo() { # newrepo <ім'я> [with-hook]
  local r="$TMP/$1"
  git init -q "$r"
  mkdir -p "$r/sub/deep"
  if [[ "${2:-}" == with-hook ]]; then
    printf '#!/bin/sh\n# lefthook generated\ncall_lefthook run pre-commit\n' >"$r/.git/hooks/pre-commit"
    chmod +x "$r/.git/hooks/pre-commit"
  fi
  echo "$r"
}
stub_lefthook() { # stub_lefthook <шлях> <код виходу>
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/sh\nexit %s\n' "$2" >"$1"
  chmod +x "$1"
}
expect() { # expect <назва> <код> <фрагмент виводу> <тека> [env...]
  local name="$1" want="$2" frag="$3" dir="$4"
  shift 4
  local out rc=0
  out="$(cd "$dir" && env -u LEFTHOOK -u LEFTHOOK_BIN PATH="$BASE_PATH" "$@" bash "$SCRIPT" 2>&1)" || rc=$?
  if [[ "$rc" == "$want" && "$out" == *"$frag"* ]]; then
    ok "$name"
  else
    bad "$name — очікував [$want] '…$frag…', отримав [$rc] '$out'"
  fi
}

run_scenarios() {
  local r
  r="$(newrepo nohook)"
  expect "хука немає → ≠0, «не встановлено»" 1 "не встановлено" "$r"

  r="$(newrepo bare with-hook)"
  expect "хук є, lefthook ніде → ≠0 і як полагодити" 1 "pnpm install" "$r"

  r="$(newrepo inpath with-hook)"
  stub_lefthook "$TMP/pathbin/lefthook" 0
  expect "lefthook у PATH → 0" 0 "OK: pre-commit → $TMP/pathbin/lefthook" "$r" PATH="$TMP/pathbin:$BASE_PATH"

  r="$(newrepo nm with-hook)"
  stub_lefthook "$r/node_modules/lefthook-$os-$arch/bin/lefthook" 0
  expect "lefthook у node_modules кореня → 0" 0 "node_modules/lefthook-$os-$arch" "$r"
  # Та сама фікстура, але запуск із глибокої підтеки: шукати треба від КОРЕНЯ.
  expect "запуск із підтеки → усе одно знайдено в корені" 0 "OK" "$r/sub/deep"

  r="$(newrepo nm-sub with-hook)"
  # Бінарник лише в node_modules ПІДТЕКИ, не кореня — хук його не знайде.
  stub_lefthook "$r/sub/node_modules/lefthook-$os-$arch/bin/lefthook" 0
  expect "lefthook лише в node_modules підтеки → ≠0 (хук його не побачить)" 1 "не знайдено" "$r/sub"

  r="$(newrepo broken with-hook)"
  stub_lefthook "$TMP/brokenbin/lefthook" 1
  expect "lefthook є, але не запускається → ≠0" 1 "не запускається" "$r" PATH="$TMP/brokenbin:$BASE_PATH"

  # ── Незалежне рев'ю №2 ───────────────────────────────────────────────────
  r="$(newrepo noop)"
  printf '#!/bin/sh\nexit 0\n' >"$r/.git/hooks/pre-commit"
  chmod +x "$r/.git/hooks/pre-commit"
  expect "хук 'exit 0' не від lefthook → ≠0 (декоративний)" 1 "не від lefthook" "$r"

  r="$(newrepo bin with-hook)"
  stub_lefthook "$TMP/lbin/lh" 0
  expect "LEFTHOOK_BIN вказує на робочий бінарник → 0" 0 "OK: pre-commit → $TMP/lbin/lh" "$r" LEFTHOOK_BIN="$TMP/lbin/lh"
  stub_lefthook "$TMP/lbin/lh-broken" 1
  expect "LEFTHOOK_BIN на бінарник, що не запускається → ≠0" 1 "не запускається" "$r" LEFTHOOK_BIN="$TMP/lbin/lh-broken"

  r="$(newrepo idx with-hook)"
  stub_lefthook "$r/node_modules/lefthook/bin/index.js" 0
  expect "lefthook/bin/index.js (як у цьому репо) → 0" 0 "node_modules/lefthook/bin/index.js" "$r"

  r="$(newrepo inst with-hook)"
  stub_lefthook "$r/node_modules/@evilmartians/lefthook-installer/bin/lefthook" 0
  expect "@evilmartians/lefthook-installer → 0" 0 "lefthook-installer" "$r"

  r="$(newrepo noexec with-hook)"
  mkdir -p "$r/node_modules/lefthook-$os-$arch/bin"
  printf '#!/bin/sh\nexit 0\n' >"$r/node_modules/lefthook-$os-$arch/bin/lefthook"
  # Файл є, але НЕ виконуваний: хук його знайде (-f) і впаде на запуску —
  # скрипт мусить сказати саме «не запускається», а не «не знайдено».
  expect "кандидат є, але без +x → ≠0 «не запускається»" 1 "не запускається" "$r"

  # Демон запускає перевірку в LINKED worktree: хук — у спільній .git/hooks
  # головного клону, node_modules — у корені самого worktree.
  r="$(newrepo main-clone with-hook)"
  git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$r" worktree add -q "$TMP/linked-wt" -b wt-branch 2>/dev/null
  expect "linked worktree без node_modules → ≠0" 1 "не знайдено" "$TMP/linked-wt"
  stub_lefthook "$TMP/linked-wt/node_modules/lefthook-$os-$arch/bin/lefthook" 0
  expect "linked worktree, lefthook у його node_modules → 0" 0 "linked-wt/node_modules" "$TMP/linked-wt"

  r="$(newrepo off with-hook)"
  expect "LEFTHOOK=0 → ≠0, бо хук вийде без перевірки" 1 "LEFTHOOK=0" "$r" PATH="$TMP/pathbin:$BASE_PATH" LEFTHOOK=0
}

run_scenarios

if [[ -z "${HOOK_LOUD_UNDER_TEST:-}" ]]; then
  mutate() { # mutate <назва> <sed-вираз>
    local m="$TMP/mutant.sh"
    sed "$2" "$HERE/check-hook-loud.sh" >"$m"
    if cmp -s "$m" "$HERE/check-hook-loud.sh"; then
      bad "мутація «$1» нічого не змінила"
      return
    fi
    if ! bash -n "$m" 2>/dev/null; then
      bad "мутація «$1» ламає синтаксис — некоректна, а не вбита"
      return
    fi
    if QUIET=1 HOOK_LOUD_UNDER_TEST="$m" bash "$0" >/dev/null 2>&1; then
      bad "мутація «$1» ВИЖИЛА"
    else
      ok "мутація «$1» убита"
    fi
  }
  mutate "тиша замість відмови" 's/^  exit 1$/  exit 0/'
  mutate "LEFTHOOK=0 не перевіряється" 's/\[\[ "\${LEFTHOOK:-}" == 0 \]\]/false/'
  mutate "шукати від cwd, а не від кореня" 's|"\$top/node_modules/lefthook-\$os-\$arch/bin/lefthook"|"$PWD/node_modules/lefthook-$os-$arch/bin/lefthook"|'
  mutate "не запускати знайдений бінарник" 's/"\$bin" version >\/dev\/null 2>&1 ||/true ||/'
  mutate "хук не від lefthook — OK" 's/^grep -q lefthook "\$hook" ||$/true ||/'
  mutate "LEFTHOOK_BIN ігнорується" 's/if \[\[ -n "\${LEFTHOOK_BIN:-}" \]\]; then/if false; then/'
  mutate "кандидат index.js прибрано" 's|"\$top/node_modules/lefthook/bin/index.js"|"/nonexistent"|'
  mutate "кандидат installer прибрано" 's|"\$top/node_modules/@evilmartians/lefthook-installer/bin/lefthook"|"/nonexistent"|'
  mutate "-f замінено на -x" 's/\[\[ -f "\$cand" \]\]/[[ -x "$cand" ]]/'
fi

if [[ "$fail" -eq 1 ]]; then
  echo "FAIL"
  exit 1
fi
[[ -z "${QUIET:-}" ]] && echo "Усі тести пройдено."
exit 0
