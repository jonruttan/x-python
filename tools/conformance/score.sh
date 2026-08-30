#!/bin/sh
# # x-python -- Python on x-lang
#
# ## tools/conformance/score.sh -- the scoreboard, ranked
#
# @description Runs the generated conformance suite and prints pass/total per
#   group, worst first -- the sorted list of what Python is asking for next.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "
#
# WHY A SECOND SCRIPT AND NOT A RUNNER FLAG.  The platform runner reports one
# global count, and per failure a line reading "FAIL: <unit>: <case>".  It has
# no way to know how many cases a unit HAS -- only how many it just watched
# fail.  gen-specs.py writes that denominator to TOTALS.tsv, so the join
# happens here rather than upstream, and the platform runner stays a runner.
#
# The exit status is the RUNNER's: a suite with failures is a failing suite,
# and a scoreboard that swallows that is a scoreboard nobody can put in CI.
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
BUNDLE="$(cd "$HERE/../.." && pwd)"
CONF="$BUNDLE/tests/conformance"

[ -f "$CONF/TOTALS.tsv" ] || {
	echo "x-python: no generated suite -- run 'make gen' first" >&2
	exit 1
}

LOG="${TMPDIR:-/tmp}/x-python-score.$$"
trap 'rm -f "$LOG"' EXIT INT TERM

set +e
# SERIAL BY DEFAULT, AND THIS ONE CRASHED A MACHINE.
#
# This forced PARALLEL=1.  The suite is 112 spec files, each booting a FULL
# XENON TOWER, and the platform runner defaults PARALLEL_JOBS to the CPU count
# -- twelve towers resident at once on this box.  The shared runner's own header
# says why that is not survivable: "a per-process guard cannot fix memory
# exhaustion from many heavy specs loading in PARALLEL; for that lower
# PARALLEL_JOBS."  The alloc ceiling bounds ONE interpreter, not twelve.
#
# The same mistake was diagnosed and removed from tools/check/langs.sh earlier
# the same day, where it merely made r7rs flaky because that gate runs six
# bundles.  Here it runs a hundred and twelve, and the failure mode is not a
# flaky number.
#
# Export PARALLEL yourself if you want it, and lower PARALLEL_JOBS with it.
X="${X:-x}" SPEC_PATH="$CONF" \
	sh "$BUNDLE/tests/spec-runner.sh" > "$LOG" 2>&1
STATUS=$?
set -e

# ANSI IS STRIPPED IN AWK, NOT IN SED, and that is not a style choice: BSD sed
# does not interpret \033 in a pattern, so the obvious one-liner silently
# matches nothing on macOS and every FAIL line keeps its colour prefix -- which
# reads as a suite where nothing failed.  awk does interpret it.
awk -F'\t' '
	FNR == NR { total[$1] = $2; next }
	{
		line = $0
		gsub(/\033\[[0-9;]*m/, "", line)
		if (substr(line, 1, 6) != "FAIL: ") next
		line = substr(line, 7)
		i = index(line, ": ")
		if (i) fail[substr(line, 1, i - 1)]++
	}
	END {
		printf "%09d\t%-26s %6s %6s   %s\n", 0, "GROUP", "PASS", "OF", "RATE"
		pt = 0; pf = 0
		for (u in total) {
			f = (u in fail) ? fail[u] : 0
			p = total[u] - f
			pt += total[u]; pf += f
			# Rank by the SIZE OF THE RED BLOCK, not by percentage: the next
			# thing worth writing is whatever is failing most, and a group of
			# one at 0% should not outrank a group of fifty-eight at 0%.
			printf "%09d\t%-26s %6d %6d   %5.1f%%\n", 100000 - f, u, p, total[u], total[u] ? (100 * p / total[u]) : 0
		}
		printf "%09d\t%-26s %6d %6d   %5.1f%%\n", 999999999, "TOTAL", pt - pf, pt, pt ? (100 * (pt - pf) / pt) : 0
	}
' "$CONF/TOTALS.tsv" "$LOG" | sort | cut -f2-

exit $STATUS
