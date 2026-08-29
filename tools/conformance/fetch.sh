#!/bin/sh
# # x-python -- Python on x-lang
#
# ## tools/conformance/fetch.sh -- acquire the pinned test corpus
#
# @description Fetches, verifies and unpacks the MicroPython test corpus named
#   by upstream.pin.xon into deps/.  Nothing here is committed.
# @author [Jon Ruttan](jonruttan@gmail.com)
# @copyright 2026 Jon Ruttan
# @license MIT No Attribution (MIT-0)
#
#     ., .,
#     {O,O}
#     (   )
#      " "
#
# THE SAME SHAPE tools/engine/fetch.sh HAS: read a pin, fetch what it names,
# verify the digest, unpack.  A corpus is a third-party tree and gets treated
# like one -- verified on arrival, kept out of the bundle, and re-fetchable from
# the pin alone.
#
# Idempotent: an already-unpacked corpus is left alone.  Delete deps/ (or run
# `make clean`) to force a re-fetch.
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
BUNDLE="$(cd "$HERE/../.." && pwd)"
PIN="$HERE/upstream.pin.xon"

# Read the pin the way every other manifest in this tree is read: textually,
# one form per line.  An unknown form is not an error here only because this
# reader takes what it needs by name rather than walking the file.
field() {
	sed -n "s/^($1 \"\([^\"]*\)\").*/\1/p" "$PIN" | head -1
}

COMMIT="$(field commit)"
RELEASE="$(field release)"
URL="$(sed -n 's|^ *"\(https://codeload[^"]*\)").*|\1|p' "$PIN" | head -1)"
WANT="$(sed -n 's/^(tarball "sha256:\([0-9a-f]*\)".*/\1/p' "$PIN" | head -1)"

[ -n "$COMMIT" ] && [ -n "$URL" ] && [ -n "$WANT" ] || {
	echo "x-python: upstream.pin.xon is missing commit, tarball url or digest" >&2
	exit 1
}

DEST="$BUNDLE/deps/micropython-$COMMIT"

if [ -d "$DEST/tests/basics" ]; then
	echo "x-python: corpus already at $DEST ($RELEASE)"
	exit 0
fi

# sha256 is spelled differently on macOS and Linux and this script runs on both.
if command -v shasum >/dev/null 2>&1; then
	sha256() { shasum -a 256 "$1" | cut -d' ' -f1; }
elif command -v sha256sum >/dev/null 2>&1; then
	sha256() { sha256sum "$1" | cut -d' ' -f1; }
else
	echo "x-python: no shasum or sha256sum -- cannot verify the corpus" >&2
	exit 1
fi

mkdir -p "$BUNDLE/deps"
TAR="$BUNDLE/deps/.micropython-$COMMIT.tar.gz"

echo "x-python: fetching micropython $RELEASE ($COMMIT)"
curl -sfL -o "$TAR" "$URL" || {
	echo "x-python: fetch failed: $URL" >&2
	exit 1
}

GOT="$(sha256 "$TAR")"
if [ "$GOT" != "$WANT" ]; then
	rm -f "$TAR"
	echo "x-python: digest mismatch for the pinned corpus" >&2
	echo "  want $WANT" >&2
	echo "  got  $GOT" >&2
	echo "" >&2
	echo "  This is not automatically tampering.  GitHub's codeload tarballs are" >&2
	echo "  regenerated rather than stored, and their compression has changed" >&2
	echo "  before, so the same commit can hash differently over time.  What it" >&2
	echo "  IS, either way, is bytes nobody pinned -- so this refuses rather" >&2
	echo "  than scoring against them." >&2
	echo "" >&2
	echo "  To re-pin deliberately, check the commit is still $COMMIT upstream," >&2
	echo "  then put the digest above into upstream.pin.xon.  To sidestep the" >&2
	echo "  tarball entirely:" >&2
	echo "    git clone https://github.com/micropython/micropython.git \\" >&2
	echo "      && git -C micropython checkout $COMMIT" >&2
	echo "  and move its tests/ to $DEST/tests" >&2
	exit 1
fi

# Only tests/ is unpacked.  The corpus is 9.5 MB of tarball and a whole
# firmware tree; this bundle wants the .py files and nothing else.
mkdir -p "$DEST"
tar xzf "$TAR" -C "$DEST" --strip-components=1 "micropython-$COMMIT/tests"
rm -f "$TAR"

echo "x-python: corpus at $DEST ($RELEASE, verified)"
