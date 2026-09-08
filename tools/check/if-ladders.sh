#!/bin/sh
# if-ladders.sh -- `match` is the primitive; a long `if` chain is not
#
#   sh tools/check/if-ladders.sh
#
# Reports every MAXIMAL nested-if ladder of four arms or more in python/*.x,
# aggregated per function as "FILE NAME COUNT LONGEST", and diffs that against
# tools/contract/if-ladders.txt in BOTH directions:
#
#   - a function absent from the manifest FAILS.  Write it as a match.
#   - more ladders, or a longer one, than the manifest allows FAILS.  The debt
#     may only shrink.
#   - a manifest row that has improved, or gone, FAILS until the row is
#     lowered or deleted -- so the file cannot rot into a list of things that
#     are fine.
#
# The manifest is the debt this check was born with, not a licence: every row
# is a function that should become a match, and the file may only get smaller.
#
# Set X to point at a particular x; otherwise the one on PATH is used.  The
# checker itself is x -- an if ladder is a SHAPE, and reading the file as
# s-expressions is the only way to see one.  A grep would count parens.
set -e

BUNDLE="$(cd "$(dirname "$0")/../.." && pwd)"
X="${X:-x}"

command -v "$X" >/dev/null 2>&1 || {
	echo "if-ladders: no x on PATH.  Set X=/path/to/x.sh and retry." >&2
	exit 1
}

MANIFEST="$BUNDLE/tools/contract/if-ladders.txt"
TMP="${TMPDIR:-/tmp}/if-ladders.$$"
trap 'rm -f "$TMP" "$TMP.want" "$TMP.have"' EXIT

# The wrapper's repo mode wants the platform's own root as the cwd, so the
# files are named absolutely and the checker runs from there.
X_ROOT="$("$X" --share-dir)"
# ONE FILE PER PROCESS: the walker reads every form of every body, and the
# largest file here is enough to trip a shared ceiling half way through -- a
# truncated report would quietly make the manifest wrong rather than loud.
for f in "$BUNDLE"/python/*.x; do
	( cd "$X_ROOT" && "$X" --no-pin -q -f "$BUNDLE/tools/check/if-ladders.x" -- "$f" )
done \
  | sed "s|^$BUNDLE/||" \
  | awk '{ n[$1" "$2]++; if ($3 > m[$1" "$2]) m[$1" "$2] = $3 }
         END { for (k in n) print k, n[k], m[k] }' \
  | sort > "$TMP.have"

grep -v '^#' "$MANIFEST" | grep -v '^[[:space:]]*$' | sort > "$TMP.want"

rc=0
while IFS=' ' read -r file name count longest; do
	[ -n "$file" ] || continue
	row=$(awk -v f="$file" -v n="$name" '$1==f && $2==n {print $3" "$4}' "$TMP.want")
	if [ -z "$row" ]; then
		echo "$file: $name has $count if ladder(s), longest $longest -- write it as a match" >&2
		rc=1
	else
		okc=${row% *}; okl=${row#* }
		if [ "$count" -gt "$okc" ] || [ "$longest" -gt "$okl" ]; then
			echo "$file: $name is now $count/$longest (manifest allows $okc/$okl) -- the debt may only shrink" >&2
			rc=1
		fi
	fi
done < "$TMP.have"

while IFS=' ' read -r file name count longest; do
	[ -n "$file" ] || continue
	now=$(awk -v f="$file" -v n="$name" '$1==f && $2==n {print $3" "$4}' "$TMP.have")
	if [ -z "$now" ]; then
		echo "$file: $name is in the manifest but has no if ladder -- delete the row" >&2
		rc=1
	else
		nc=${now% *}; nl=${now#* }
		if [ "$nc" -lt "$count" ] || [ "$nl" -lt "$longest" ]; then
			echo "$file: $name is down to $nc/$nl (manifest says $count/$longest) -- lower the row" >&2
			rc=1
		fi
	fi
done < "$TMP.want"

if [ "$rc" = 0 ]; then
	echo "if-ladders: $(wc -l < "$TMP.have" | tr -d ' ') function(s) carrying known debt, none new"
fi
exit $rc
