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

. "$X_ROOT/tests/spec-runner.sh"
