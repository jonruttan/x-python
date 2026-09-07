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

# THE SUITE BOOTS FROM A STATE IMAGE OF THE HARNESS, when the platform can
# write one -- and for this bundle the boot IS the suite's cost.  Measured on
# CI: 65 spec files, 41 minutes on one job, and the EMPTY harness spec takes
# 26 seconds, so two thirds of the wall clock is the tower and this runtime
# being read from source once per file.  Nothing about a file is slow; the
# boot is, 65 times over.
#
# tools/dev/image-build.sh images a child base that loaded the harness and
# keys the image on everything it depends on -- the harness, the platform's
# lib/, its engine, and python/ (the KEY-PATH) -- so an edit to any of them
# rewrites it (a few seconds) and a current one is skipped.  What makes this
# possible here at all is the transient work in #42: a second base is its own
# chain and holds words no image can name, so until %py-base and %py-sexp-base
# were nilled in a transient thunk and remade on load, this library was
# REFUSED by the writer.  The bundle's own boot measured 0.9s from the image
# against 10.8s from source there; the image this writes holds 193,455 objects
# and reports `unnameable: 0`, which is that work showing up as a number.
#
# MEASURED HERE, three files against themselves (00-harness, 01-tokenizer,
# 15-operators, same machine, same 47 cases green either way): 54s from
# source, 27s including the image write, 7s from a current image.  The whole
# suite from the image is 609 cases green in 7m24s.
#
# The writer lives in a CHECKOUT only; an installed tree boots from source and
# says so.  IMG=0 is the control: the same suite from source, for when the
# image is the suspect -- and it is the FIRST thing to try against a failure
# that reproduces nowhere else, because a stale or wrong image is invisible in
# a diff.
if [ "${IMG:-1}" = 0 ]; then
	# Nothing to undo: this runner already names its spec files explicitly, so
	# it is one process per file either way and the boot is the ONLY thing
	# that differs between the control and the image run.
	:
else
	_builder="$X_ROOT/tools/dev/image-build.sh"
	if [ -f "$_builder" ]; then
		if X_BIN="$X_BIN" sh "$_builder" "$LANG_LIB" "$BUNDLE/tests/lib/.images" "$BUNDLE/python"; then
			X_IMG_DIR="$BUNDLE/tests/lib/.images"; export X_IMG_DIR
		else
			echo "x-python: no state image (image-build exit $?) -- the suite boots from source" >&2
		fi
	else
		echo "x-python: no image writer at $_builder (not a checkout) -- the suite boots from source" >&2
	fi
fi

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

# SHARDS, BECAUSE THE BOOT IS THE COST.  Measured on CI: 65 files, 41 minutes,
# and the EMPTY harness spec takes 26s -- so two thirds of the wall time is the
# tower booting 65 times over, and no single file is the problem.  Those boots
# are independent, so the honest speedup is to pay them on more machines at
# once: SPEC_SHARD=i/n keeps every n-th file starting at the i-th (0-based),
# and n jobs given 0/n .. n-1/n run the whole suite between them with nothing
# shared and nothing skipped.  Round-robin rather than contiguous ranges, so
# the heavy files that cluster by number spread across shards.  Unset means
# one shard of one, the runner's old behaviour, which is what a local run and
# the release gate want.
case "${SPEC_SHARD:-}" in
	"") ;;
	*/*)
		i="${SPEC_SHARD%/*}"; n="${SPEC_SHARD#*/}"
		k=0
		for f in "$@"; do
			if [ $((k % n)) -eq "$i" ]; then set -- "$@" "$f"; fi
			k=$((k + 1))
			shift
		done
		[ "$#" -gt 0 ] || { echo "x-python: shard $SPEC_SHARD selects no files" >&2; exit 1; }
		;;
	*)
		echo "x-python: SPEC_SHARD must be i/n, got '$SPEC_SHARD'" >&2
		exit 1
		;;
esac

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

# SIZE THE UNIT TIMEOUT FOR THE SLOWEST LANE.  On the pinned v0.9.0
# platform the boot runs interpreted (its analyser burst needs a cwd only
# a checkout has), so a spec file on CI's runners costs ~25-30s of boot
# before its first case -- and as the bundle grew, every file crept toward
# the 60-second default until whichever was heaviest that week tipped over
# (exit 124), each time reading as a regression that was not one.  Three
# file splits later the honest fix is the knob the platform runner
# documents: the guard still bounds a runaway, at a ceiling sized for a
# boot the slow lane actually pays.  A timeout kill here also strands an
# orphan engine at full spin -- observed taking a CI host down (exit 143)
# -- so a ceiling nothing legitimate hits is safer than a tight one.
# RAISED AGAIN, 120 -> 300, for the reason the paragraph above gives.  CI
# runners vary by ~30% run to run (measured: identical specs at 21s and
# 26s, 38s and 49s, on two runs of the same suite days apart), and this
# bundle boots the whole tower per file.  A file that fits in 120s on a
# fast runner does not on a slow one, and the kill takes the HOST down
# rather than failing one case -- twice, at the same file boundary, with
# "Terminate orphan process (timeout)" in the cleanup and exit 143.
export TIMEOUT_UNIT_SECS="${TIMEOUT_UNIT_SECS:-300}"

# SIZE THE CEILING FOR THE CONFORMANCE BATCHES ONLY, as the platform
# runner's own comment instructs a seam-collect opt-out to do.  With no
# per-snippet collect a conformance file's 15-case batch accumulates every
# case's parse-time garbage, and the float family's heaviest file crossed
# the 300M default when the expression ladder grew its bitwise levels --
# the interpreter died mid-batch three cases from the end, which reads as
# a regression and is a resource limit.
#
# SCOPED, NOT GLOBAL, and the first attempt is why: raising the default
# for the whole suite let one file's ceiling exceed CI's 16GB runner, and
# the HOST killed the runner (exit 143, "received a shutdown signal") --
# an object ceiling is only a guard while it is smaller than the machine.
# The spec suite never needed the headroom; only `make conformance` does,
# and only locally.
case "${SPEC_PATH:-}" in
	*/conformance)
		export X_ALLOC_LIMIT_OBJS="${X_ALLOC_LIMIT_OBJS:-450000000}"
		;;
esac

. "$X_ROOT/tests/spec-runner.sh"
