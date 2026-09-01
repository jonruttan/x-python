#!/bin/sh
# # x-python -- Python on x-lang
#
# ## tests/spec-runner.sh -- the bundle's runner
#
# @description Sources the PLATFORM's spec runner; vendors nothing.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "
#
# NOT ONE PATH INTO THE X-LANG SOURCE TREE.  Everything comes from x itself:
# --share-dir says which tree x reads from (repo root in a checkout, share/x
# installed) and --engine-path says where the engine is after the wrapper's
# full discovery order.  The 2024 personalities reached the platform with
# "$SCRIPT_DIR/../../../tests/spec-runner.sh" and dangled the moment they left
# the repo -- the failure docs/personality-contract.md calls "addressing,
# not sharing".
#
# NEVER INVOKE THE ENGINE DIRECTLY.  The runner's whole-process timeout is the
# runaway guard, and it also arms an alloc-limit! ceiling; x has no depth limit
# on non-tail calls (x-lang#56), so ordinary-looking input can recurse until the
# machine locks up.  Probes belong in a .spec.md, which is slower per probe and
# is the only sanctioned path.
#
# Set X to point at a particular x; otherwise the one on PATH is used.
# Set SPEC_PATH to run a directory other than tests/specs -- `make conformance`
# points it at tests/conformance.
set -e

BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"
X="${X:-x}"

command -v "$X" >/dev/null 2>&1 || {
	echo "x-python: no x on PATH.  Set X=/path/to/x.sh and retry." >&2
	exit 1
}

X_ROOT="$("$X" --share-dir)"
# X_BIN is env-overridable, the way tests/x/spec-runner.sh makes it -- so the
# same runner can drive a variant or patched engine without moving anything.
X_BIN="${X_BIN:-$("$X" --engine-path)}"

# REQUIRED FROM AN INSTALLED TREE.  The runner finds its awk harness from the
# directory holding the ENGINE -- true in a checkout, where the binary sits
# beside tests/, and false in an install, where the engine is under libexec/x.
# A sourced script cannot portably find its own path, so the caller says.
SPEC_RUNNER_DIR="$X_ROOT/tests"
export SPEC_RUNNER_DIR

# HOSTED BOOT, AND IT IS WORTH 3x THE SUITE'S WALL CLOCK.  The platform's
# boot compiles its reader analysers through the cc lane, gated by
# %compile-hosted? -- which probes engine/include RELATIVE TO CWD (compile.x's
# design assumes `engine` points at the engine wherever x runs).  A bundle
# checkout has no such entry, so every spec here booted with INTERPRETED
# analysers: 23.6s per file against 7.8s hosted, measured on the same tree.
# The engine release dir ships include/ for exactly this purpose, so the
# runner points `engine` at the engine it is already using.  The link is a
# machine fact (gitignored, never committed), refreshed when the engine moves,
# and left alone if the user placed their own.
X_ENGINE_ROOT="$(dirname "$X_BIN")"
if [ -d "$X_ENGINE_ROOT/include" ]; then
	if [ -L "$BUNDLE/engine" ] && [ "$(readlink "$BUNDLE/engine")" != "$X_ENGINE_ROOT" ]; then
		rm -f "$BUNDLE/engine"
	fi
	[ -e "$BUNDLE/engine" ] || ln -s "$X_ENGINE_ROOT" "$BUNDLE/engine"
fi

# The harness is GENERATED, never committed: it embeds two absolute paths that
# are facts of this machine, not of the bundle.
sh "$BUNDLE/tests/gen-harness.sh" "$X_ROOT" "$BUNDLE"

LANG_LIB="$BUNDLE/tests/lib/harness.gen.x"
SPEC_PATH="${SPEC_PATH:-$BUNDLE/tests/specs}"

[ -d "$SPEC_PATH" ] || {
	echo "x-python: no specs at $SPEC_PATH" >&2
	echo "  for the conformance suite, run 'make gen' first" >&2
	exit 1
}

# ONE PROCESS PER SPEC FILE, and this is a resource fix rather than a
# preference.
#
# With no arguments the shared runner BUCKETS files by their @lib and runs each
# bucket in one interpreter. Every spec here shares one harness, so the whole
# suite became a single process -- and a batch has no auto-GC, so it accumulates
# every case's parse-time garbage until it exits. At 207 cases that was fine; at
# 232 it crossed the alloc-limit! ceiling and 24 cases reported "no result".
#
# Measured, not guessed: the same 207 cases fail when the ceiling is LOWERED to
# 40M, and all 232 pass when the files are passed as arguments -- which the
# shared runner spawns individually.
#
# So the files are named explicitly. Each gets its own process and its own
# ceiling, and the suite can grow without a resource limit masquerading as a
# regression. The cost is one library boot per file.
if [ "$#" -eq 0 ]; then
	set -- "$SPEC_PATH"/*.spec.md
fi

# NO COLLECT AT SNIPPET SEAMS.  python-run builds an isolated tokenizer base,
# which is C-held state the collector's mark cannot see (the x-lang#283 rooting
# family) -- so the platform runner's per-seam collect (x-lang#568) frees it
# LIVE, and the third eval in a process walks freed memory and segfaults.
# x-lang#572 added this run-level door out; this suite opts out wholesale,
# which is the right granularity because every generated conformance case
# shares the one python-run eval path.  This restores the accumulate-then-exit
# regime the suite was calibrated under; the alloc ceiling still bounds a
# file's batch, as before.  A runner without the knob (v0.9.0) ignores it.
export SPEC_SEAM_COLLECT=0

. "$X_ROOT/tests/spec-runner.sh"
