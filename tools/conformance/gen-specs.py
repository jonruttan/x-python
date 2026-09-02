#!/usr/bin/env python3
# # x-python -- Python on x-lang
#
# ## tools/conformance/gen-specs.py -- corpus -> .spec.md
#
# @description Turns the pinned MicroPython test corpus into .spec.md files
#   whose expected output is a real CPython run.
# @author Jon Ruttan <jonruttan@gmail.com>
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
# WHY THIS ONE TOOL IS NOT SH.  Everything else in this bundle is POSIX sh on
# principle.  This is the one place where the dependency is already hard --
# CPython IS the oracle, so a machine that cannot run this script cannot
# generate a suite anyway -- and the work is escaping Python source into x-lang
# string literals, which sh would do badly and unreadably.
#
# WHAT IT REFUSES, AND WHY EACH ONE IS RECORDED.  A generator that silently
# drops what it cannot express reads as "682 tests" when it means "610".  Every
# exclusion below is counted and written to tests/conformance/SKIPPED.md with a
# reason, so the score's denominator is auditable.
#
#   cpython-refused   CPython will not run the file (builtin_help, memoryerror,
#                     the *_micropython ones).  Upstream's .exp records
#                     MicroPython's OWN deviation and this bundle has no
#                     business chasing it.
#   nondeterministic  two CPython runs under different PYTHONHASHSEED disagree.
#                     id(), set ordering, addresses.  Nothing can match it.
#   prompt-prefix     an output line starts with "> " or "$ ".  The spec runner
#                     strips those as REPL prompts from CAPTURED output, so the
#                     comparison could never succeed.  A harness artefact, not
#                     a Python fact.
#   separator-clash   an output line is literally <<SEP>>, the runner's own
#                     case delimiter.  It would desync the whole batch.
#   fence-clash       the output contains ``` and would close the expected
#                     block early.
#   oversize          source or output past the caps below.  Keeps one spec
#                     file readable and one awk batch sane.
#   empty-output      the program prints nothing, so the assertion has no
#                     content to be wrong about.

import os
import subprocess
import sys

# The caps are generous on purpose.  They exist so one spec file stays readable
# and one awk batch stays sane, not to trim the suite: at these values the only
# programs they catch are the bignum and float-formatting torture tests, which
# print thousands of lines.  Raising them is a decision anyone can make -- the
# names they exclude are listed in SKIPPED.md, so the cost of the cap is visible
# rather than inferred.
MAX_SRC = 20000       # chars of Python source in one x-lang string literal
MAX_OUT_LINES = 500   # lines of expected output in one case
MAX_OUT_CHARS = 40000

REASONS = [
    "cpython-refused", "nondeterministic", "prompt-prefix",
    "separator-clash", "fence-clash", "oversize", "empty-output",
]


def xstr(s):
    """Escape a Python program into an x-lang string literal.

    x-lang escapes \\" \\\\ \\n \\t \\r \\0 \\xHH.  Braces need no escaping:
    interpolation is a property of $"..." strings, not of plain ones.  Non-ASCII
    goes through as UTF-8, which the reader takes (#\\EUR is legal everywhere).
    """
    out = []
    for ch in s:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\0":
            out.append("\\0")
        elif ord(ch) < 0x20 or ord(ch) == 0x7F:
            out.append("\\x%02x" % ord(ch))
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def run_cpython(path, seed):
    env = dict(os.environ, PYTHONHASHSEED=str(seed))
    try:
        p = subprocess.run(
            [sys.executable, os.path.basename(path)],
            cwd=os.path.dirname(path), env=env,
            capture_output=True, text=True, timeout=15,
        )
    except (subprocess.TimeoutExpired, UnicodeDecodeError):
        return None
    if p.returncode != 0:
        return None
    return p.stdout


def normalise(out):
    """Match the runner's own comparison: leading and trailing blank lines are
    not significant in ```output mode; interior ones are."""
    lines = out.split("\n")
    while lines and lines[0].strip() == "":
        lines.pop(0)
    while lines and lines[-1].strip() == "":
        lines.pop()
    return lines


def group_of(stem):
    head = stem.split("_")[0]
    return head.rstrip("0123456789") or head


def main():
    corpus, outdir, suites = sys.argv[1], sys.argv[2], sys.argv[3:]
    os.makedirs(outdir, exist_ok=True)
    for old in os.listdir(outdir):
        if old.endswith(".spec.md") or old in ("SKIPPED.md", "TOTALS.tsv"):
            os.remove(os.path.join(outdir, old))

    groups = {}     # (suite, group) -> [(name, src, want_lines)]
    skipped = []    # (suite/name, reason)

    for suite in suites:
        sdir = os.path.join(corpus, "tests", suite)
        if not os.path.isdir(sdir):
            print("x-python: no %s in the corpus" % suite, file=sys.stderr)
            continue
        for fn in sorted(os.listdir(sdir)):
            if not fn.endswith(".py"):
                continue
            path = os.path.join(sdir, fn)
            rel = "%s/%s" % (suite, fn)

            try:
                src = open(path, encoding="utf-8").read()
            except UnicodeDecodeError:
                skipped.append((rel, "oversize"))
                continue

            a = run_cpython(path, 0)
            if a is None:
                skipped.append((rel, "cpython-refused"))
                continue
            b = run_cpython(path, 1)
            if b != a:
                skipped.append((rel, "nondeterministic"))
                continue

            want = normalise(a)
            if not want:
                skipped.append((rel, "empty-output"))
                continue
            if any(ln.startswith("> ") or ln.startswith("$ ") for ln in want):
                skipped.append((rel, "prompt-prefix"))
                continue
            if any(ln == "<<SEP>>" for ln in want):
                skipped.append((rel, "separator-clash"))
                continue
            if any("```" in ln for ln in want):
                skipped.append((rel, "fence-clash"))
                continue
            if (len(src) > MAX_SRC or len(want) > MAX_OUT_LINES
                    or sum(len(ln) for ln in want) > MAX_OUT_CHARS):
                skipped.append((rel, "oversize"))
                continue

            key = (suite, group_of(fn[:-3]))
            groups.setdefault(key, []).append((fn, src, want))

    total = 0
    # ONE PROCESS PER FILE, AND A FILE IS AT MOST CHUNK CASES.  The runner
    # batches a file's cases into one no-auto-GC process, and a 49-case
    # group (basics/string) crossed the object ceiling around its eighth
    # case, so the forty-one after it read as dead when they were never
    # run.  Chunking keeps every case measurable; the heading is the same
    # in every chunk so the scoreboard's per-group tally is unchanged.
    CHUNK = 10
    for (suite, group), cases in sorted(groups.items()):
      nchunks = (len(cases) + CHUNK - 1) // CHUNK
      for ci in range(nchunks):
        chunk = cases[ci * CHUNK:(ci + 1) * CHUNK]
        suffix = "" if nchunks == 1 else "-%d" % (ci + 1)
        out = os.path.join(outdir, "%s-%s%s.spec.md" % (suite, group, suffix))
        with open(out, "w", encoding="utf-8") as fh:
            fh.write(HEADER % (suite, group, len(cases)))
            fh.write("## %s/%s\n\n" % (suite, group))
            for fn, src, want in chunk:
                fh.write("### %s\n\n" % fn)
                fh.write("```python\n(python-run %s)\n```\n" % xstr(src))
                fh.write("---\n```output\n%s\n```\n\n" % "\n".join(want))
        total += len(chunk)

    with open(os.path.join(outdir, "SKIPPED.md"), "w", encoding="utf-8") as fh:
        fh.write(SKIPPED_HEADER % (MAX_SRC, MAX_OUT_LINES, MAX_OUT_CHARS))
        for reason in REASONS:
            hits = [n for n, r in skipped if r == reason]
            fh.write("## %s (%d)\n\n" % (reason, len(hits)))
            for n in sorted(hits):
                fh.write("- `%s`\n" % n)
            fh.write("\n")

    # TOTALS.tsv is what turns the runner's wall of failures into a table.
    # The runner reports one global count and prints "FAIL: <unit>: <case>" per
    # failure; it has no idea how many cases a unit HAS.  This file knows, so
    # score.sh can subtract and rank.
    with open(os.path.join(outdir, "TOTALS.tsv"), "w", encoding="utf-8") as fh:
        for (suite, group), cases in sorted(groups.items()):
            fh.write("%s/%s\t%d\n" % (suite, group, len(cases)))

    print("x-python: %d cases in %d spec files, %d skipped"
          % (total, len(groups), len(skipped)))
    print("x-python: exclusions and their reasons in %s/SKIPPED.md" % outdir)


HEADER = """<!-- GENERATED by tools/conformance/gen-specs.py.  Do not edit and
do not commit: this file is derived from the MicroPython corpus pinned in
tools/conformance/upstream.pin.xon (MIT), and its expected output is a real
CPython run on this machine.  Regenerate with: make gen

Suite %s, group %s, %d cases.  Each case is one whole program compared on its
whole stdout -- the output-fenced expected block, not the default last-line
compare, because a conformance case that only checks its last line is not
checking the program.
-->

"""

SKIPPED_HEADER = """<!-- GENERATED by tools/conformance/gen-specs.py. -->

# What the generator refused, and why

The score's denominator is only honest if this file exists.  Each section is a
reason the generator could not turn an upstream program into a spec case; the
reasons themselves are documented at the top of `gen-specs.py`.

A name here is not a failing test.  It is a test that was never asked.

The oversize caps in force: %d chars of source, %d lines of output, %d chars of
output.

"""

if __name__ == "__main__":
    main()
