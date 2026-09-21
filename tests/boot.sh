#!/bin/sh
# # x-python -- Python on x-lang
#
# ## tests/boot.sh -- the bundle boots the way a user boots it
#
# @description Runs a short program through `x -l python`, on the dialect
#   lang.xon declares, and compares what it prints.
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
# The program is small on purpose.  It asks for one thing from each table the
# bundle builds while it loads -- a string escape, a big integer, a float, a
# dict -- and the specs cover the rest.
set -u

BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"

X="${X:-x}"
command -v "$X" >/dev/null 2>&1 || {
	echo "x-python: no x on PATH.  Set X=/path/to/x.sh and retry." >&2
	exit 1
}

_TMP="${TMPDIR:-/tmp}/x-python-boot.$$"
trap 'rm -rf "$_TMP"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$_TMP/langs"

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

cat > "$_TMP/program.py" <<'EOF'
print('\x41' + 'b')
print(2 ** 100)
print(1 / 4)
print(sorted({'b': 1, 'a': 2}))
EOF

cat > "$_TMP/want" <<'EOF'
Ab
1267650600228229401496703205376
0.25
['a', 'b']
EOF

# --no-image: the boot under test is the one from source.  An image would
# answer from whatever tree wrote it.
( cd "$SPAWN_DIR" && "$X" -q --no-image -l python -f "$_TMP/program.py" ) \
	> "$_TMP/got" 2> "$_TMP/err"
status=$?

if [ "$status" -ne 0 ]; then
	echo "x-python: x -l python exited $status" >&2
	sed 's/^/    /' "$_TMP/err" | head -20 >&2
	sed 's/^/    /' "$_TMP/got" | head -20 >&2
	exit 1
fi

if ! diff -u "$_TMP/want" "$_TMP/got" > "$_TMP/diff"; then
	echo "x-python: x -l python booted, and the program printed something else" >&2
	sed 's/^/    /' "$_TMP/diff" >&2
	sed 's/^/    /' "$_TMP/err" | head -20 >&2
	exit 1
fi

echo "x-python: x -l python boots on the declared dialect and runs a program"
