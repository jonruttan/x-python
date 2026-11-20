#!/bin/sh
# # x-python -- Python on x-lang
#
# ## tests/boot.sh -- the bundle boots the way a user boots it
#
# @description Boots the bundle from source through `x -l python`, on the
#   dialect lang.xon declares, runs a short program, and compares what it
#   prints.
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
# boots the declared dialect and reads run.x, which is the path that finds
# such a name: the load stops with `Unbound SYMBOL`.
#
# From source, with --no-image: the boot under test is this tree's, not
# whatever tree wrote an image, and the bundle sweeps between its files on
# every source boot (python/util.x), so the load fits.
#
# The program goes in as a user's does, a Python file given with -f, which
# the wrapper cats after run.x and run.x's last form reads (python-batch,
# python/repl.x).  It is small on purpose: one thing from each table the
# bundle builds while it loads -- a string escape, a big integer, a float, a
# dict -- and the specs cover the rest.  It has what only a file has: a
# blank line inside a block, an expression statement that must print
# nothing, and a last line.
#
# A second program raises and catches nothing: its error is on standard
# error, what it printed first is on standard output, and the status is 1.
set -u

BUNDLE="$(cd "$(dirname "$0")/.." && pwd)"

X="${X:-x}"
command -v "$X" >/dev/null 2>&1 || {
	echo "x-python: no x on PATH.  Set X=/path/to/x.sh and retry." >&2
	exit 1
}

_TMP="${TMPDIR:-/tmp}/x-python-boot.$$"
mkdir -p "$_TMP/langs"

# What the runs wrote so far, for a run that did not end on its own.
show() {
	for f in err got; do
		[ -s "$_TMP/$f" ] && sed 's/^/    /' "$_TMP/$f" | tail -20 >&2
	done
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

cat > "$_TMP/program.py" <<'EOX'
print('\x41' + 'b')
print(2 ** 100)
print(1 / 4 < 1)
print(sorted({'b': 1, 'a': 2}))

def fact(n):
    if n <= 1:
        return 1

    return n * fact(n - 1)

fact(3)
print(fact(20))
print([7, 8, 9][1], [7, 8, 9][-1])
EOX

cat > "$_TMP/want" <<'EOX'
Ab
1267650600228229401496703205376
True
['a', 'b']
2432902008176640000
8 9
EOX

cat > "$_TMP/raises.py" <<'EOX'
print("before")
raise ValueError("no")
print("after")
EOX

# Stdin is closed off so the run owes nothing to whatever the caller's is.
# The address-space cap turns a boot that grows past it into an engine exit
# instead of a machine out of memory: a load that stopped sweeping would
# show here first.  macOS does not enforce the cap.
run_x() {
	(
		cd "$SPAWN_DIR" || exit 1
		ulimit -v 12000000 2>/dev/null
		"$X" "$@"
	) < /dev/null
}

run_x -q --no-image -l python -f "$_TMP/program.py" > "$_TMP/got" 2> "$_TMP/err"
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

echo "x-python: x -l python boots from source on the declared dialect and runs a program"

run_x -q --no-image -l python -f "$_TMP/raises.py" > "$_TMP/got" 2> "$_TMP/err"
status=$?
if [ "$status" -ne 1 ] || [ "$(cat "$_TMP/got")" != before ] \
	|| ! grep -q '^Error: .*no' "$_TMP/err"; then
	echo "x-python: a program that raises: status $status, wanted 1," >&2
	echo "  'before' on standard output and the error on standard error" >&2
	show
	exit 1
fi

echo "x-python: a program that raises ends with status 1 and its error on standard error"
