#!/bin/sh
# # x-python -- Python on x-lang
#
# ## tests/boot.sh -- the bundle boots the way a user boots it
#
# @description Boots the bundle through `x -l python`, on the dialect
#   lang.xon declares, runs a short program, and compares what it prints.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
# Usage:
#   X=/path/to/x.sh sh tests/boot.sh
#
# This complements the spec suite.  The suite loads the bundle on the
# full-tower amalgam (tests/gen-harness.sh), which binds more names than the
# declared dialect does, so a platform name the bundle reads and never binds
# can be bound for the suite and unbound for `x -l python`.  Here the wrapper
# boots the declared dialect, reads run.x and runs a program, which is the
# path that finds such a name: the boot stops with `Unbound SYMBOL`.
#
# The program goes in as the specs send theirs, a `python-run` form in a
# file the wrapper reads after run.x.  It is small on purpose: one thing from
# each table the bundle builds while it loads -- a string escape, a big
# integer, a float, a dict -- and the specs cover the rest.
set -u

BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"

X="${X:-x}"
command -v "$X" >/dev/null 2>&1 || {
	echo "x-python: no x on PATH.  Set X=/path/to/x.sh and retry." >&2
	exit 1
}

_TMP="${TMPDIR:-/tmp}/x-python-boot.$$"
mkdir -p "$_TMP/langs"

# What the run wrote so far, for a run that did not end on its own.
show() {
	[ -s "$_TMP/err" ] && sed 's/^/    /' "$_TMP/err" | tail -20 >&2
	[ -s "$_TMP/got" ] && sed 's/^/    /' "$_TMP/got" | tail -20 >&2
}
trap 'rm -rf "$_TMP"' EXIT
trap 'echo "x-python: interrupted" >&2; show; exit 130' INT
trap 'echo "x-python: terminated" >&2; show; exit 143' TERM

# The wrapper searches X_LANG_DIR for the bundle that calls itself "python"
# and refuses when two do.  A directory holding one link to this tree answers
# with this tree whatever else sits beside it -- another checkout, a worktree.
ln -s "$BUNDLE" "$_TMP/langs/python"
X_LANG_DIR="$_TMP/langs/"
export X_LANG_DIR

# A checkout's x.sh finds its library relative to the current directory, so
# it is run from its own root; an installed x runs from anywhere.
X_ROOT="$("$X" --share-dir)"
if [ -e "$X_ROOT/lib/x.x" ]; then
	SPAWN_DIR="$X_ROOT"
else
	SPAWN_DIR="$BUNDLE"
fi

# An x form, as the specs write one: the reader unescapes \\ and \n, so the
# program Python sees has a \x41 escape and four lines.
cat > "$_TMP/program.x" <<'EOX'
(python-run "print('\\x41' + 'b')\nprint(2 ** 100)\nprint(1 / 4)\nprint(sorted({'b': 1, 'a': 2}))")
EOX

cat > "$_TMP/want" <<'EOX'
Ab
1267650600228229401496703205376
0.25
['a', 'b']
EOX

# --no-image: the boot under test is the one from source.  An image would
# answer from whatever tree wrote it.  Stdin is closed off so the run owes
# nothing to whatever the caller's is.
( cd "$SPAWN_DIR" && "$X" -q --no-image -l python -f "$_TMP/program.x" ) \
	< /dev/null > "$_TMP/got" 2> "$_TMP/err"
status=$?

if [ "$status" -ne 0 ]; then
	echo "x-python: x -l python exited $status" >&2
	show
	exit 1
fi

if ! diff -u "$_TMP/want" "$_TMP/got" > "$_TMP/diff"; then
	echo "x-python: x -l python booted, and the program printed something else" >&2
	sed 's/^/    /' "$_TMP/diff" >&2
	show
	exit 1
fi

echo "x-python: x -l python boots on the declared dialect and runs a program"
