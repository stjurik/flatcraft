#!/usr/bin/env bash
# guard-destructive.sh — хук PreToolUse (Bash) профілю оркестратора: руйнівні git- і
# rm-команди в ~/hart і постійних worktree блокуються в будь-якій відомій формі.
#
# ЧОМУ ЦЕ ІСНУЄ. Deny-правило профілю ловить РЯДОК команди, а не ДІЮ. Тричі заборону
# обійшла інша форма: #151 (force-push), #167 (`CLAUDE.md` правили інтерпретатором) і
# 2026-10-06 — субагент отримав відмову на `git reset --hard` / `git clean` і досяг
# того самого через `git checkout -- <файли>` і `rm`. Правило трьох (CLAUDE.md §0 п.6)
# → механізм замість речення в інструкції (#216, рішення yurii 2026-10-08, варіант а).
#
# ЩО ЛОВИТЬ. Захищене дерево — `~/hart`, сама тека `~/hart-wt`, кожен постійний worktree
# `~/hart-wt/<ім'я>` і будь-який їхній предок (`rm -rf ~`). Тимчасові worktree
# `~/hart-wt/tmp-*` — НЕ захищені: там руйнівні команди дозволені.
#   - git: `reset --hard`; `clean` (крім `-n`/`--dry-run`); `checkout` з `--`, `.`,
#     `-f`, `-p`, шаблоном або наявним файлом серед аргументів; `restore` (крім лише
#     `--staged`); `stash drop|clear`; `branch -D` (і `-d` з `-f`);
#     `worktree remove --force` — ціль тут шлях worktree, а не тека виклику.
#   - `rm` з будь-яким шляхом у захищеному дереві; `find … -delete` і `find … -exec rm`
#     (ціль — початкові теки find); `xargs rm` (ціль — тека виклику: шляхи з stdin
#     відносні до неї).
#   - Ціль визначається за `cwd` події, `cd`/`pushd` у ланцюжку, `git -C`,
#     `--git-dir`/`--work-tree`, `GIT_DIR=`/`GIT_WORK_TREE=` і явними шляхами `rm`/`find`.
#   - Ланцюжки `&&`, `||`, `;`, `|`, `&`, перенос рядка, `( … )`, `$( … )`, зворотні
#     лапки; `bash|sh|dash|zsh|ksh -c "…"` — розбирається рекурсивно; обгортки
#     `env`, `command`, `exec`, `nohup`, `nice`, `timeout`, `time`, `xargs`, `VAR=…`.
#   - Невизначена ціль — захищена (fail closed): `$ЗМІННА`, `~user`, `{a,b}`, `cd -`,
#     відносний шлях без `cwd`. Нерозібрана команда чи подія — теж блок.
#
# ЧОГО НЕ ДОВОДИТЬ — чесно:
#   - Інтерпретатори: `python -c "shutil.rmtree(…)"`, `perl -e unlink`, `node -e` хук
#     не ловить — він читає рядок команди, а не дію. Повну межу дає лише пісочниця
#     Claude Code (#216, варіант б, клас A — рішення yurii).
#   - Скрипт-файл (`bash x.sh`), `git -c alias.x='!…'`, `$( … )` всередині подвійних
#     лапок, `find -exec sh -c …`, `mv`/`cp` поверх файла, `>` перенаправлення,
#     `unlink`, `shred`; шляхи, що приходять у `xargs rm` з stdin абсолютними.
#   - Сховище stash і гілки спільні для всіх worktree одного репо: `git stash clear`
#     чи `git branch -D` у `tmp-*` дозволені (так у #216), хоч зачіпають і ~/hart.
#   - Автономний профіль A8 — інша межа (контейнер, #151), цей хук його не стосується.
#
# Протокол Claude Code: stdin — JSON події (`tool_name`, `tool_input.command`, `cwd`);
# exit 2 + причина в stderr — виклик заблоковано; exit 0 — пропущено. Будь-який
# ІНШИЙ код Claude Code вважає не-блокуючою помилкою й пропускає команду, тому
# падіння самого хука (немає python3, виняток) перетворюється на exit 2, а не на 1.
#
# Використання (як хук): bash ~/.flatcraft/hooks/guard-destructive.sh <подія.json
# Ставить install-orchestrator-profile.sh; тест — guard-destructive.test.sh.
set -uo pipefail

command -v python3 >/dev/null 2>&1 || {
  echo "guard-destructive: немає python3 — команду не перевірено, тому заблоковано" >&2
  exit 2
}

read -r -d '' PY <<'PY' || true
import glob
import json
import os
import re
import shlex
import sys

HOME = os.path.realpath(os.path.expanduser("~"))
HART = os.path.join(HOME, "hart")
WT = os.path.join(HOME, "hart-wt")
ROOTS = [os.path.realpath(HART), os.path.realpath(WT)]
SHELLS = {"bash", "sh", "dash", "zsh", "ksh"}
KEYWORDS = {"{", "}", "!", "if", "then", "else", "elif", "fi", "do", "done", "while", "until", "time"}
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


class Block(Exception):
    pass


def resolve(path, cwd):
    """Абсолютний шлях або None — ціль невизначена."""
    if path is None or any(c in path for c in "$`{"):
        return None
    if path == "~" or path.startswith("~/"):
        path = HOME + path[1:]
    elif path.startswith("~"):
        return None
    if not os.path.isabs(path):
        if cwd is None:
            return None
        path = os.path.join(cwd, path)
    return os.path.normpath(path)


def protected_abs(p):
    p = os.path.realpath(p)
    for root in ROOTS:
        if p == root or root.startswith(p.rstrip("/") + "/"):
            return True  # сам корінь або його предок
    if p.startswith(ROOTS[0] + "/"):
        return True
    if p.startswith(ROOTS[1] + "/"):
        return not p[len(ROOTS[1]) + 1 :].split("/")[0].startswith("tmp-")
    return False


def protected(path, cwds):
    for cwd in cwds:
        p = resolve(path, cwd)
        if p is None:
            return True
        cands = [p] + (glob.glob(p) if any(c in p for c in "*?[") else [])
        if any(protected_abs(c) for c in cands):
            return True
    return False


def chdir(cwds, path):
    return [resolve(path, c) for c in cwds]


def lex(cmd):
    """Сегменти команди: [(токени, роздільник після)]."""
    lx = shlex.shlex(cmd, posix=True, punctuation_chars=";&|()<>\n`")
    lx.whitespace = " \t\r"
    lx.whitespace_split = True
    try:
        tokens = list(lx)
    except ValueError as e:
        raise Block(f"команду не розібрано ({e})")
    segs, cur, depth = [], [], 0
    for t in tokens:
        sep = None
        if t and set(t) <= set(";&|\n`"):
            sep = t
        elif t == "(" and (not cur or cur[-1] == "$"):
            # `(` — роздільник лише на початку команди чи після `$`; інакше це
            # аргумент (`find . \( … \)`).
            if cur and cur[-1] == "$":
                cur.pop()
            depth += 1
            sep = t
        elif t == ")" and depth > 0:
            depth -= 1
            sep = t
        if sep is not None:
            segs.append((cur, sep))
            cur = []
        else:
            cur.append(t)
    segs.append((cur, None))
    return [(s, sep) for s, sep in segs if s]


def drop_redirects(tokens):
    out, skip = [], False
    for t in tokens:
        if skip:
            skip = False
        elif t and set(t) <= set("<>&|") and ("<" in t or ">" in t):
            skip = True
        else:
            out.append(t)
    return out


def unwrap(tokens):
    """Прибирає VAR=…, ключові слова shell і обгортки; повертає (команда, env)."""
    env, i = {}, 0
    while i < len(tokens):
        t, base = tokens[i], os.path.basename(tokens[i])
        if t in KEYWORDS:
            i += 1
        elif ASSIGN.match(t):
            k, _, v = t.partition("=")
            env[k] = v
            i += 1
        elif base in ("command", "builtin", "exec", "nohup", "stdbuf"):
            i += 1
            while i < len(tokens) and tokens[i].startswith("-"):
                i += 1
        elif base == "env":
            i += 1
            while i < len(tokens) and (tokens[i].startswith("-") or ASSIGN.match(tokens[i])):
                if tokens[i] in ("-C", "--chdir"):
                    raise Block("env -C: тека виконання невизначена")
                if ASSIGN.match(tokens[i]):
                    k, _, v = tokens[i].partition("=")
                    env[k] = v
                i += 2 if tokens[i] in ("-u", "--unset", "-S") else 1
        elif base == "nice":
            i += 1
            if i < len(tokens) and tokens[i] == "-n":
                i += 2
            elif i < len(tokens) and tokens[i].startswith("-"):
                i += 1
        elif base == "timeout":
            i += 1
            while i < len(tokens) and tokens[i].startswith("-"):
                i += 2 if tokens[i] in ("-s", "-k", "--signal", "--kill-after") else 1
            i += 1  # тривалість
        else:
            break
    return tokens[i:], env


def short_flags(args):
    s = set()
    for a in args:
        if a.startswith("-") and not a.startswith("--") and len(a) > 1:
            s.update(a[1:])
    return s


def git_check(args, cwds, env):
    cur, extra, i = list(cwds), [], 0
    for k in ("GIT_DIR", "GIT_WORK_TREE"):
        if k in env:
            extra.append(env[k])
    while i < len(args):
        a = args[i]
        if a == "-C" and i + 1 < len(args):
            cur = chdir(cur, args[i + 1])
            i += 2
            continue
        if a in ("--git-dir", "--work-tree") and i + 1 < len(args):
            extra.append(args[i + 1])
            i += 2
            continue
        if a.startswith("--git-dir=") or a.startswith("--work-tree="):
            extra.append(a.partition("=")[2])
            i += 1
            continue
        if a in ("-c", "--namespace", "--exec-path", "--config-env") and i + 1 < len(args):
            i += 2
            continue
        if a.startswith("-"):
            i += 1
            continue
        break
    if i >= len(args):
        return
    sub, rest = args[i], args[i + 1 :]
    sf, opts = short_flags(rest), set(rest)
    what, targets = None, None
    if sub == "reset" and "--hard" in opts:
        what = "git reset --hard"
    elif sub == "clean" and not ("n" in sf or "--dry-run" in opts):
        what = "git clean"
    elif sub == "checkout":
        pos, skip = [], False
        for a in rest:
            if skip:
                skip = False
            elif a in ("-b", "-B", "--orphan"):
                skip = True
            elif not a.startswith("-"):
                pos.append(a)
        on_disk = any(
            c is not None and os.path.lexists(os.path.join(c, p)) for p in pos for c in cur
        )
        if (
            "--" in opts
            or {"f", "p"} & sf
            or {"--force", "--patch"} & opts
            or any(p == "." or p.startswith(":") or any(ch in p for ch in "*?[") for p in pos)
            or on_disk
        ):
            what = "git checkout (відкат файлів)"
    elif sub == "restore":
        staged = "S" in sf or "--staged" in opts
        worktree = "W" in sf or "--worktree" in opts
        if worktree or not staged:
            what = "git restore"
    elif sub == "stash" and rest and rest[0] in ("drop", "clear"):
        what = f"git stash {rest[0]}"
    elif sub == "branch":
        if "D" in sf or (("d" in sf or "--delete" in opts) and ("f" in sf or "--force" in opts)):
            what = "git branch -D"
    elif sub == "worktree" and rest and rest[0] == "remove":
        r = rest[1:]
        if "f" in short_flags(r) or "--force" in r:
            what = "git worktree remove --force"
            paths = [a for a in r if not a.startswith("-")]
            if paths:
                targets = [(p, cur) for p in paths]
    if what is None:
        return
    if targets is None:
        targets = [(".", cur)]
    targets += [(e, cwds) for e in extra]
    for path, base in targets:
        if protected(path, base):
            raise Block(f"{what} у захищеному дереві ({path})")


def rm_check(args, cwds, what="rm"):
    paths, end = [], False
    for a in args:
        if not end and a == "--":
            end = True
        elif not end and a.startswith("-") and a != "-":
            continue
        else:
            paths.append(a)
    for p in paths:
        if protected(p, cwds):
            raise Block(f"{what} у захищеному дереві ({p})")


def find_check(args, cwds):
    i = 0
    while i < len(args) and args[i] in ("-H", "-L", "-P"):
        i += 1
    starts = []
    while i < len(args) and not (args[i].startswith("-") or args[i] in ("(", ")", "!", ",")):
        starts.append(args[i])
        i += 1
    expr = args[i:]
    destructive = "-delete" in expr
    for j, a in enumerate(expr[:-1]):
        if a in ("-exec", "-execdir", "-ok", "-okdir") and os.path.basename(expr[j + 1]) == "rm":
            destructive = True
    if destructive:
        rm_check(["--"] + (starts or ["."]), cwds, "find -delete / -exec rm")


def xargs_check(args, cwds, depth):
    i, ph = 0, None
    valued = ("-I", "-n", "-L", "-P", "-d", "-a", "-E", "-s", "-l")
    while i < len(args) and args[i].startswith("-"):
        a = args[i]
        if a == "-I" and i + 1 < len(args):
            ph = args[i + 1]
            i += 2
        elif a.startswith("-I"):
            ph = a[2:]
            i += 1
        elif a == "-i" or a.startswith("--replace"):
            ph = a.partition("=")[2] or "{}"
            i += 1
        elif a in valued:
            i += 2
        else:
            i += 1
    sub = [t for t in args[i:] if t != ph]
    if not sub:
        return
    if os.path.basename(sub[0]) == "rm":
        rm_check(sub[1:] + ["--", "."], cwds, "xargs rm")
    else:
        segment(sub, cwds, depth)


def shell_script(args):
    found, i = False, 0
    while i < len(args):
        a = args[i]
        if a in ("-o", "+o"):
            i += 2
            continue
        if a == "--":
            i += 1
            break
        if a.startswith("-") or a.startswith("+"):
            if not a.startswith("--") and "c" in a[1:]:
                found = True
            i += 1
            continue
        break
    if found and i < len(args):
        return args[i]
    return None


def segment(tokens, cwds, depth):
    """Перевіряє одну просту команду; повертає нові теки, якщо це cd."""
    tokens, env = unwrap(drop_redirects(tokens))
    if not tokens:
        return None
    prog, args = os.path.basename(tokens[0]), tokens[1:]
    if prog in ("cd", "pushd"):
        dest = [a for a in args if not a.startswith("-")]
        if not dest:
            return [HOME] if prog == "cd" and not args else [None]
        return chdir(cwds, dest[0])
    if prog == "popd":
        return [None]
    if prog in SHELLS:
        script = shell_script(args)
        if script is not None:
            check(script, cwds, depth + 1)
    elif prog == "eval":
        check(" ".join(args), cwds, depth + 1)
    elif prog == "git":
        git_check(args, cwds, env)
    elif prog == "rm":
        rm_check(args, cwds)
    elif prog == "find":
        find_check(args, cwds)
    elif prog == "xargs":
        xargs_check(args, cwds, depth)
    return None


def check(cmd, cwds, depth=0):
    if depth > 8:
        raise Block("занадто глибока вкладеність shell -c")
    cur, fallback = list(cwds), []
    for tokens, sep in lex(cmd):
        new = segment(tokens, cur, depth)
        if new is not None:
            if sep in ("&&", "|"):
                # `cd X && …` — далі лише в X; але після `;`/`||` знов можлива стара тека.
                fallback, cur = fallback + cur, new
            else:
                cur = cur + new
        if sep not in (None, "&&", "|", "(", ")"):
            cur, fallback = cur + fallback, []
        cur = list(dict.fromkeys(cur))


def main():
    try:
        ev = json.loads(sys.stdin.read())
    except ValueError:
        raise Block("подію хука не розібрано")
    if not isinstance(ev, dict):
        raise Block("подію хука не розібрано")
    if ev.get("tool_name", "Bash") != "Bash":
        return
    cmd = (ev.get("tool_input") or {}).get("command")
    if not isinstance(cmd, str):
        raise Block("у події немає tool_input.command")
    cwd = ev.get("cwd")
    check(cmd, [os.path.normpath(cwd) if isinstance(cwd, str) and os.path.isabs(cwd) else None])


try:
    main()
except Block as e:
    print(
        f"guard-destructive: заблоковано — {e}. Захищені ~/hart і постійні worktree "
        "~/hart-wt/<гілка>; руйнівні команди дозволені лише в ~/hart-wt/tmp-*. "
        "Відмова → STOP і звіт, не інша форма команди (orchestrator-autonomy.md §6, #216).",
        file=sys.stderr,
    )
    sys.exit(2)
except Exception as e:  # noqa: BLE001 — будь-яке падіння має блокувати, а не пропускати
    print(f"guard-destructive: збій перевірки ({type(e).__name__}) — заблоковано", file=sys.stderr)
    sys.exit(2)
PY

exec python3 -c "$PY"
