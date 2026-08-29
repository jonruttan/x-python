#!/bin/sh
# # x-python -- Python on x-lang
#
# ## tools/conformance/gen-specs.sh -- generate tests/conformance/
#
# @description Locates the fetched corpus and the CPython oracle, then runs
#   gen-specs.py over the suites upstream.pin.xon names.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
BUNDLE="$(cd "$HERE/../.." && pwd)"
PIN="$HERE/upstream.pin.xon"

COMMIT="$(sed -n 's/^(commit "\([^"]*\)").*/\1/p' "$PIN" | head -1)"
SUITES="$(sed -n 's/^(suites \(.*\))$/\1/p' "$PIN" | head -1 | tr -d '"')"
CORPUS="$BUNDLE/deps/micropython-$COMMIT"

[ -d "$CORPUS/tests" ] || {
	echo "x-python: no corpus at $CORPUS -- run 'make fetch' first" >&2
	exit 1
}

# THE ORACLE IS A REAL CPYTHON, and which one is a fact worth printing: the
# expected output in tests/conformance/ is whatever THIS interpreter said, so a
# score is only comparable between machines running the same one.
PY="${PYTHON:-python3}"
command -v "$PY" >/dev/null 2>&1 || {
	echo "x-python: no python3 -- the conformance suite needs CPython as its oracle" >&2
	echo "  set PYTHON=/path/to/python3 to name one" >&2
	exit 1
}
echo "x-python: oracle $("$PY" -V 2>&1) at $(command -v "$PY")"

"$PY" "$HERE/gen-specs.py" "$CORPUS" "$BUNDLE/tests/conformance" $SUITES
