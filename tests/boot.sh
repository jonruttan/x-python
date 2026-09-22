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
# The program goes in as the specs send theirs, `python-run` forms in a file
# the wrapper reads after run.x.  It is small on purpose: one thing from each
# table the bundle builds while it loads -- a string escape, a big integer, a
# float, a dict -- and the specs cover the rest.  Each line runs on a swept
# heap, so the peak this check reaches is the load's and not the probe's;
# on x-lang 0.14.0 the two together passed the cap below.
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

# x forms, as the specs write them: the reader unescapes \\, so the first
# program Python sees has a \x41 escape.  A collect between the lines, as
# the platform's own boots collect between their groups.
cat > "$_TMP/program.x" <<'EOX'
(python-run "print('\\x41' + 'b')")
((prim-ref (lit heap) (lit collect)))
(python-run "print(2 ** 100)")
((prim-ref (lit heap) (lit collect)))
(python-run "print(1 / 4 < 1)")
((prim-ref (lit heap) (lit collect)))
(python-run "print(sorted({'b': 1, 'a': 2}))")
EOX

cat > "$_TMP/want" <<'EOX'
Ab
1267650600228229401496703205376
True
['a', 'b']
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

run_x -q --no-image -l python -f "$_TMP/program.x" > "$_TMP/got" 2> "$_TMP/err"
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
