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
# ЩО ЛОВИТЬ. Захищені: `~/hart`, сама тека `~/hart-wt`, кожен постійний worktree
# `~/hart-wt/<ім'я>`, `~/.flatcraft` (копія самого хука) і будь-який їхній предок
# (`rm -rf ~`). Тимчасові worktree `~/hart-wt/tmp-*` — НЕ захищені.
#   - git: `reset --hard`; `clean` (крім `-n`/`--dry-run`); `checkout` з `--`, `.`,
#     `-f`, `-p`, шаблоном або наявним файлом серед аргументів; `restore` (крім лише
#     `--staged`); `switch -f|--discard-changes`; `rm -f`; `checkout-index -f`;
#     `read-tree -u`. Довгі опції — і скорочені (`--har`), бо git їх приймає.
#   - Спільний стан репо — блок ЗАВЖДИ, з будь-якої теки, зокрема з `tmp-*`: stash,
#     гілки й reflog спільні для всіх worktree, тож `git stash drop|clear`,
#     `git branch -D` (і `-d` з `-f`), `git reflog expire|delete` у `tmp-*` руйнують і
#     ~/hart (рішення yurii: «руйнівні в ~/hart — у будь-якій формі»).
#     `git worktree remove` — блок, якщо worktree не `tmp-*`; ціль тут шлях worktree.
#     Відносний аргумент git спершу читає як ім'я (останні компоненти шляху), тож він —
#     невизначена ціль: дозволено лише абсолютний шлях чи `~/…`.
#   - `rm` з будь-яким шляхом у захищеному дереві; `find … -delete`, `find … -exec <будь-що>`
#     (перевіряється як команда); `xargs <команда>` (ціль — тека виклику).
#   - Ціль — за `cwd` події, `cd`/`pushd` у ланцюжку, `git -C`, `--git-dir`/`--work-tree`,
#     `-c core.worktree=`, `GIT_DIR`/`GIT_WORK_TREE` (і через `export` раніше в команді)
#     і явними шляхами `rm`/`find`. Шлях під щойно створеним у тій самій команді
#     `ln`/`mv`/`git worktree move` — невизначений.
#   - Розбір: ланцюжки `&& || ; | & ;;`, перенос рядка, `\`+перенос (склеювання),
#     `{ … }`, `( … )`, `$( … )`, `<( … )`, зворотні лапки (і всередині слова: `VAR=$(…)`,
#     `"$(…)"`); вміст `( … )` і `$( … )` — підоболонка, її `cd` теку назовні не змінює;
#     `cd` у конвеєрі чи фоні — теж. Тіло heredoc з лапками в розділювачі (`<<'EOF'`) —
#     дані, не команда; без лапок — лише його `$( … )`. `#` коментарем не вважається
#     (у bash `a#b`, `$#` — не коментар): помилка в бік блоку.
#   - `bash|sh|dash|zsh|ksh|fish -c "…"`, `eval "…"`, `env -S "…"` — рекурсивно; обгортки
#     `env`, `command`, `builtin`, `exec`, `nohup`, `nice`, `timeout`, `time`, `setsid`,
#     `ionice`, `stdbuf`, `xargs`, `VAR=…` — з їхніми опціями.
#   - Невизначене — захищене (fail closed): ціль `$ЗМІННА`, `~user`, `{a,b}`, `cd -`,
#     відносний шлях без `cwd`; слово команди чи підкоманда git зі `$`/підстановкою
#     (`$x -rf`, `git $s --hard`, `eval "$cmd"`); оболонка, що читає команду з stdin
#     (`… | bash`, `bash <<< …`), — блок, якщо ціль захищена. Нерозібрана команда чи
#     подія — блок.
#
# ЧОГО НЕ ДОВОДИТЬ — чесно:
#   - Інтерпретатори: `python -c "shutil.rmtree(…)"`, `perl -e unlink`, `node -e` хук
#     не ловить — він читає рядок команди, а не дію. Повну межу дає лише пісочниця
#     Claude Code (#216, варіант б, клас A — рішення yurii).
#   - Скрипт-файл (`bash x.sh`), git-аліаси (`git -c alias.x='!…'`, свої аліаси yurii),
#     функції, оголошені в ІНШОМУ виклику, `mv`/`cp` поверх файла, `>` перенаправлення,
#     `unlink`, `shred`; шляхи, що приходять у `xargs rm` з stdin абсолютними.
#   - Запис у копію хука перенаправленням (`> ~/.flatcraft/hooks/…`) — його тримає лише
#     deny `Edit(~/.flatcraft/**)` і `--check`.
#   - Автономний профіль A8 — інша межа (контейнер, #151), цей хук його не стосується.
#
# Протокол Claude Code: stdin — JSON події (`tool_name`, `tool_input.command`, `cwd`);
# exit 2 + причина в stderr — виклик заблоковано; exit 0 — пропущено. Будь-який
# ІНШИЙ код Claude Code вважає не-блокуючою помилкою й пропускає команду, тому
# падіння самого хука (немає python3, виняток) — exit 2, а команда хука в профілі
# закінчується `|| exit 2`: зникла чи зламана копія (127, 126) теж блокує.
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
HART = os.path.realpath(os.path.join(HOME, "hart"))
WT = os.path.realpath(os.path.join(HOME, "hart-wt"))
FLAT = os.path.realpath(os.path.join(HOME, ".flatcraft"))
SHELLS = {"bash", "sh", "dash", "zsh", "ksh", "fish"}
KEYWORDS = {"!", "if", "then", "else", "elif", "fi", "do", "done", "while", "until",
            "function", "case", "esac", "for", "select", "in"}
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
# Операції shell: shlex склеює сусідню пунктуацію в один токен (`);`, `&&(`), тож
# такий токен розрізається на відомі операції, найдовші першими.
OPS = sorted(["&&", "||", ";;&", ";;", ";&", "|&", "&>>", "&>", "<<<", "<<-", "<<", ">>",
              "<(", ">(", ">&", "<&", ">|", "(", ")", ";", "&", "|", "<", ">", "\n", "`"],
             key=len, reverse=True)
SEPS = {"&&", "||", ";;&", ";;", ";&", "|", "|&", ";", "&", "\n", "{", "}"}
REDIRS = {"<", ">", ">>", "<<", "<<-", "<<<", ">&", "<&", "&>", "&>>", ">|"}
# Обгортка → опції зі значенням окремим словом.
WRAPPERS = {
    "command": set(), "builtin": set(), "nohup": set(), "setsid": set(),
    "exec": {"-a"},
    "nice": {"-n", "--adjustment"},
    "time": {"-f", "-o", "--format", "--output"},
    "timeout": {"-s", "-k", "--signal", "--kill-after"},
    "ionice": {"-c", "-n", "-p", "-P", "-u", "--class", "--classdata", "--pid", "--pgid", "--uid"},
    "stdbuf": {"-i", "-o", "-e", "--input", "--output", "--error"},
}
TAINT = []  # шляхи, створені чи переміщені `ln`/`mv` у цій самій команді
SHELL_ENV = {}  # GIT_DIR / GIT_WORK_TREE, присвоєні будь-де в команді


class Block(Exception):
    pass


def literal(word):
    return not any(c in word for c in "$`")


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


def under(p, root):
    return p == root or p.startswith(root.rstrip("/") + "/")


def protected_abs(p):
    raw, p = p, os.path.realpath(p)
    for t in TAINT:
        if t is None or under(raw, t) or under(p, t):
            return True
    for root in (HART, WT, FLAT):
        if under(root, p):
            return True  # сам корінь або його предок
    if under(p, HART) or under(p, FLAT):
        return True
    if p.startswith(WT + "/"):
        return not p[len(WT) + 1 :].split("/")[0].startswith("tmp-")
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


def strip_heredocs(cmd):
    """Прибирає тіла heredoc. Розділювач у лапках — тіло лише дані; без лапок — у тілі
    лишаються тільки `$( … )` і `` `…` ``: їх bash виконує."""
    out, i, n, stack, pending = [], 0, len(cmd), ["top"], []
    while i < n:
        c, ctx = cmd[i], stack[-1]
        if c == "\\":
            out.append(cmd[i : i + 2])
            i += 2
            continue
        if ctx == "dq":
            if c == '"':
                stack.pop()
            elif cmd.startswith("$(", i):
                stack.append("sub")
                out.append("$(")
                i += 2
                continue
            out.append(c)
            i += 1
            continue
        if c == "'":
            j = cmd.find("'", i + 1)
            j = n - 1 if j < 0 else j
            out.append(cmd[i : j + 1])
            i = j + 1
            continue
        if c == '"':
            stack.append("dq")
        elif cmd.startswith("$(", i):
            stack.append("sub")
            out.append("$(")
            i += 2
            continue
        elif c == ")" and ctx == "sub":
            stack.pop()
        elif cmd.startswith("<<", i) and not cmd.startswith("<<<", i):
            j = i + 2
            tabs = j < n and cmd[j] == "-"
            j += 1 if tabs else 0
            while j < n and cmd[j] in " \t":
                j += 1
            k, word, quoted = j, "", False
            while k < n and cmd[k] not in " \t\n;&|<>()":
                ch = cmd[k]
                if ch in "'\"":
                    e = cmd.find(ch, k + 1)
                    e = n if e < 0 else e
                    word, quoted, k = word + cmd[k + 1 : e], True, e + 1
                elif ch == "\\":
                    word, quoted, k = word + cmd[k + 1 : k + 2], True, k + 2
                else:
                    word, k = word + ch, k + 1
            if word:
                pending.append((word, quoted, tabs))
            out.append(cmd[i:k])
            i = k
            continue
        elif c == "\n" and pending:
            out.append("\n")
            i += 1
            for word, quoted, tabs in pending:
                body = []
                while i < n:
                    e = cmd.find("\n", i)
                    line, i = (cmd[i:], n) if e < 0 else (cmd[i:e], e + 1)
                    if (line.lstrip("\t") if tabs else line) == word:
                        break
                    body.append(line)
                if not quoted:
                    out.extend(s + "\n" for s in substitutions("\n".join(body)))
            pending = []
            continue
        out.append(c)
        i += 1
    return "".join(out)


def tokenize(cmd):
    lx = shlex.shlex(cmd, posix=True, punctuation_chars=";&|()<>\n`")
    lx.whitespace = " \t\r"
    lx.whitespace_split = True
    lx.commenters = ""  # `#` у bash коментар не скрізь (`a#b`, `$#`) — краще зайвий блок
    try:
        raw = list(lx)
    except ValueError as e:
        raise Block(f"команду не розібрано ({e})")
    tokens = []
    for t in raw:
        if t and set(t) <= set(";&|()<>\n`"):
            i = 0
            while i < len(t):
                op = next(o for o in OPS + [t[i]] if t.startswith(o, i))
                tokens.append(op)
                i += len(op)
        else:
            tokens.append(t)
    return tokens


def parse(tokens, i=0, closer=None):
    """Сегменти: [(токени, роздільник після, вкладені групи)]. Вкладена група —
    `( … )`, `$( … )`, `<( … )`, `` `…` ``: перевіряється окремо, теку назовні не змінює."""
    segs, cur, groups, argdepth = [], [], [], 0
    while i < len(tokens):
        t = tokens[i]
        if closer == "`" and t == "`":
            return segs + [(cur, None, groups)], i + 1
        if closer == ")" and t == ")" and argdepth == 0:
            return segs + [(cur, None, groups)], i + 1
        if t == "`" or t in ("<(", ">(") or (t == "(" and (not cur or cur[-1].endswith("$"))):
            # Підстановка (`$(`, `` ` ``, `<(`) дає слово з невідомим вмістом — «$(…)»;
            # підоболонка `( … )` на місці команди — нічого, крім своєї групи.
            word = "(…)" if t == "(" and not cur else "$(…)"
            if t == "(" and cur:
                word = cur.pop()[:-1] + word
            inner, i = parse(tokens, i + 1, "`" if t == "`" else ")")
            groups.append(inner)
            cur.append(word)
            continue
        if t == "(":
            argdepth += 1
            cur.append(t)
        elif t == ")" and argdepth:
            argdepth -= 1
            cur.append(t)
        elif t in SEPS or t == ")":
            # `)` поза групою — шаблон `case`; далі нова команда.
            segs.append((cur, t, groups))
            cur, groups = [], []
        else:
            cur.append(t)
        i += 1
    return segs + [(cur, None, groups)], i


def substitutions(word):
    """Тексти `$( … )` і `` `…` `` усередині одного слова (лапки shlex уже зняв)."""
    out, i = [], 0
    while i < len(word):
        if word.startswith("$(", i):
            depth, j = 1, i + 2
            while j < len(word) and depth:
                depth += {"(": 1, ")": -1}.get(word[j], 0)
                j += 1
            out.append(word[i + 2 : j - 1] if depth == 0 else word[i + 2 :])
            i = j
        elif word[i] == "`":
            j = word.find("`", i + 1)
            out.append(word[i + 1 :] if j < 0 else word[i + 1 : j])
            i = len(word) if j < 0 else j + 1
        else:
            i += 1
    return out


def drop_redirects(tokens):
    out, skip = [], False
    for t in tokens:
        if skip:
            skip = False
        elif t in REDIRS:
            skip = True
        else:
            out.append(t)
    return out


def skip_opts(tokens, i, valued):
    while i < len(tokens) and tokens[i].startswith("-") and tokens[i] != "-":
        if tokens[i] == "--":
            return i + 1
        i += 2 if tokens[i] in valued else 1
    return i


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
        elif base in WRAPPERS:
            i = skip_opts(tokens, i + 1, WRAPPERS[base])
            if base == "timeout":
                i += 1  # тривалість
        elif base == "env":
            i += 1
            while i < len(tokens) and (tokens[i].startswith("-") or ASSIGN.match(tokens[i])):
                t = tokens[i]
                if t in ("-C", "--chdir") or t.startswith("--chdir="):
                    raise Block("env -C: тека виконання невизначена")
                if t in ("-S", "--split-string") or t.startswith("-S") or t.startswith("--split-string="):
                    # `env -S "<рядок>"` розбиває рядок на команду й аргументи
                    # (рецензія Flash #218, дефект 3).
                    if t in ("-S", "--split-string"):
                        value, after = (tokens[i + 1] if i + 1 < len(tokens) else ""), i + 2
                    else:
                        value, after = (t.partition("=")[2] if t.startswith("--") else t[2:]), i + 1
                    try:
                        tokens = shlex.split(value) + tokens[after:]
                    except ValueError:
                        raise Block("env -S: рядок не розібрано")
                    i = 0
                    break
                if ASSIGN.match(t):
                    k, _, v = t.partition("=")
                    env[k] = v
                i += 2 if t in ("-u", "--unset") else 1
        else:
            break
    return tokens[i:], env


def short_flags(args):
    s = set()
    for a in args:
        if a.startswith("-") and not a.startswith("--") and len(a) > 1:
            s.update(a[1:])
    return s


def lopt(args, name):
    """Є довга опція name — повна чи скорочена (git приймає однозначні скорочення)."""
    return any(a.startswith("--") and len(a) > 2 and name.startswith(a.split("=", 1)[0])
               for a in args)


def git_check(args, cwds, env):
    cur, extra, i = list(cwds), [], 0
    for k in ("GIT_DIR", "GIT_WORK_TREE"):
        for src in (env, SHELL_ENV):
            if k in src:
                extra.append(src[k])
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
            if a == "-c" and args[i + 1].lower().startswith("core.worktree="):
                extra.append(args[i + 1].partition("=")[2])
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
    what, targets, shared = None, None, False
    if not literal(sub):
        what = "git з невизначеною підкомандою"
    elif sub == "reset" and lopt(rest, "--hard"):
        what = "git reset --hard"
    elif sub == "clean" and not ("n" in sf or lopt(rest, "--dry-run")):
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
            or lopt(rest, "--force")
            or lopt(rest, "--patch")
            or any(p == "." or p.startswith(":") or any(ch in p for ch in "*?[") for p in pos)
            or on_disk
        ):
            what = "git checkout (відкат файлів)"
    elif sub == "switch" and ("f" in sf or lopt(rest, "--force") or lopt(rest, "--discard-changes")):
        what = "git switch --discard-changes"
    elif sub == "rm" and ("f" in sf or lopt(rest, "--force")):
        what = "git rm -f"
    elif sub == "checkout-index" and ("f" in sf or lopt(rest, "--force")):
        what = "git checkout-index -f"
    elif sub == "read-tree" and "u" in sf:
        what = "git read-tree -u"
    elif sub == "restore":
        staged = "S" in sf or lopt(rest, "--staged")
        worktree = "W" in sf or lopt(rest, "--worktree")
        if worktree or not staged:
            what = "git restore"
    elif sub == "stash" and rest and rest[0] in ("drop", "clear"):
        what, shared = f"git stash {rest[0]}", True
    elif sub == "reflog" and rest and rest[0] in ("expire", "delete"):
        # stash — це reflog refs/stash: `reflog expire` знищує його записи.
        what, shared = f"git reflog {rest[0]}", True
    elif sub == "branch":
        if "D" in sf or (("d" in sf or lopt(rest, "--delete")) and ("f" in sf or lopt(rest, "--force"))):
            what, shared = "git branch -D", True
    elif sub == "worktree" and rest and rest[0] in ("move", "mv"):
        TAINT.extend(resolve(a, c) for a in rest[1:] if not a.startswith("-") for c in cur)
    elif sub == "worktree" and rest and rest[0] == "remove":
        r = rest[1:]
        what = "git worktree remove"
        paths = [a for a in r if not a.startswith("-")]
        if paths:
            # git спершу шукає worktree за унікальним останнім компонентом шляху
            # (`git help worktree`: «ghi or def/ghi is enough»), і лише потім — як
            # шлях від теки виклику. Тож відносний аргумент — невизначена ціль
            # (рецензія Flash #218, дефект 4); дозволено лише абсолютний шлях чи `~/…`.
            targets = [(p, cur if os.path.isabs(p) or p == "~" or p.startswith("~/") else [None])
                       for p in paths]
    if what is None:
        return
    if shared:
        raise Block(f"{what} — stash, гілки й reflog спільні для всіх worktree, це руйнує й ~/hart")
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


def find_check(args, cwds, depth):
    i = 0
    while i < len(args) and (args[i] in ("-H", "-L", "-P") or re.match(r"^-O\d*$", args[i])
                             or args[i] == "-D"):
        i += 2 if args[i] == "-D" else 1
    starts = []
    while i < len(args) and not (args[i].startswith("-") or args[i] in ("(", ")", "!", ",")):
        starts.append(args[i])
        i += 1
    expr = args[i:]
    if "-delete" in expr:
        rm_check(["--"] + (starts or ["."]), cwds, "find -delete")
    for j, a in enumerate(expr):
        if a not in ("-exec", "-execdir", "-ok", "-okdir"):
            continue
        cmd = []
        for t in expr[j + 1 :]:
            if t in (";", "+"):
                break
            cmd.append(t)
        if cmd and os.path.basename(cmd[0]) == "rm":
            rm_check(["--"] + (starts or ["."]), cwds, "find -exec rm")
        elif cmd:
            # -exec — у теці виклику find; -execdir — у теці кожного знайденого файла.
            base = cwds if a in ("-exec", "-ok") else [r for s in (starts or ["."]) for r in chdir(cwds, s)]
            segment([t for t in cmd if t != "{}"], base, depth)


XARGS_VALUED = {"-I", "-n", "-L", "-P", "-d", "-a", "-E", "-s", "--arg-file", "--delimiter",
                "--max-args", "--max-procs", "--max-chars", "--process-slot-var"}


def xargs_check(args, cwds, depth):
    i, ph = 0, None
    while i < len(args) and args[i].startswith("-"):
        a = args[i]
        if a == "--":
            i += 1
            break
        if a == "-I" and i + 1 < len(args):
            ph = args[i + 1]
            i += 2
        elif a.startswith("-I"):
            ph = a[2:]
            i += 1
        elif a == "-i" or a.startswith("--replace"):
            ph = a.partition("=")[2] or "{}"
            i += 1
        elif a in XARGS_VALUED:
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


SHELL_VALUED = {"-o", "+o", "-O", "+O", "--rcfile", "--init-file"}


def shell_script(args):
    """('c', рядок) | ('file', шлях) | ('stdin', None)."""
    found, stdin, i = False, False, 0
    while i < len(args):
        a = args[i]
        if a in SHELL_VALUED:
            i += 2
            continue
        if a == "--":
            i += 1
            break
        if a.startswith("-") or a.startswith("+"):
            if not a.startswith("--") and "c" in a[1:]:
                found = True
            if not a.startswith("--") and "s" in a[1:]:
                stdin = True
            i += 1
            continue
        break
    if found:
        return ("c", args[i]) if i < len(args) else ("stdin", None)
    if stdin or i >= len(args):
        return ("stdin", None)
    return ("file", args[i])


def undefined(what, args, cwds):
    """Невідома команда: блок, якщо захищена тека виклику чи будь-який шлях-аргумент."""
    if any(protected(".", [c]) for c in cwds) or any(
        protected(a, cwds) for a in args if not a.startswith("-")
    ):
        raise Block(f"{what} — що виконається, не визначено, а ціль захищена")


def segment(tokens, cwds, depth):
    """Перевіряє одну просту команду; повертає нові теки, якщо це cd."""
    tokens, env = unwrap(drop_redirects(tokens))
    for k in ("GIT_DIR", "GIT_WORK_TREE"):
        if k in env and not tokens:
            SHELL_ENV[k] = env[k]  # `GIT_DIR=…; git …` — присвоєння без команди
    if not tokens:
        return None
    prog, args = os.path.basename(tokens[0]), tokens[1:]
    if not literal(tokens[0]):
        undefined(f"команда «{tokens[0]}»", args, cwds)
        return None
    if prog in ("export", "declare", "typeset", "readonly", "local"):
        for a in args:
            k, eq, v = a.partition("=")
            if eq and k in ("GIT_DIR", "GIT_WORK_TREE"):
                SHELL_ENV[k] = v
        return None
    if prog in ("cd", "pushd"):
        dest = [a for a in args if not a.startswith("-")]
        if not dest:
            return [HOME] if prog == "cd" and not args else [None]
        return chdir(cwds, dest[0])
    if prog == "popd":
        return [None]
    if prog in ("ln", "mv"):
        TAINT.extend(resolve(a, c) for a in args if not a.startswith("-") for c in cwds)
    elif prog in SHELLS:
        kind, script = shell_script(args)
        if kind == "c":
            check(script, cwds, depth + 1)
        elif kind == "stdin":
            undefined(f"{prog} читає команду з stdin", [], cwds)
    elif prog == "eval":
        if not all(literal(a) for a in args):
            undefined("eval з підстановкою", args, cwds)
        check(" ".join(args), cwds, depth + 1)
    elif prog == "git":
        git_check(args, cwds, env)
    elif prog == "rm":
        rm_check(args, cwds)
    elif prog == "find":
        find_check(args, cwds, depth)
    elif prog == "xargs":
        xargs_check(args, cwds, depth)
    return None


def run(segs, cwds, depth):
    cur, fallback, prev = list(cwds), [], None
    for tokens, sep, groups in segs:
        for g in groups:
            run(g, cur, depth + 1)  # підоболонка: її cd назовні не діє
        for t in tokens:
            # `"$(…)"`, `a$(…)`, `"`…`"` — підстановка всередині слова: вкладена команда.
            for inner in substitutions(t):
                check(inner, cur, depth + 1)
        new = segment(tokens, cur, depth)
        # Команди конвеєра (`|`) і фонові (`&`) — окремі підпроцеси: `cd` у них теку
        # для наступних команд не змінює (рецензія Flash #218, дефект 1).
        subshell = sep in ("|", "|&", "&") or prev in ("|", "|&")
        if new is not None and not subshell:
            if sep == "&&":
                # `cd X && …` — далі лише в X; але після `;`/`||` знов можлива стара тека.
                fallback, cur = fallback + cur, new
            else:
                cur = cur + new
        if sep not in (None, "&&", "|", "|&"):
            cur, fallback = cur + fallback, []
        cur = list(dict.fromkeys(cur))
        prev = sep


def check(cmd, cwds, depth=0):
    if depth > 8:
        raise Block("занадто глибока вкладеність")
    cmd = strip_heredocs(cmd.replace("\\\n", ""))
    segs, _ = parse(tokenize(cmd))
    run(segs, cwds, depth)


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
