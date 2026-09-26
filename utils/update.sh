#!/bin/sh
# Usage: utils/update.sh                 show pinned versions and what upstream offers
#        utils/update.sh <name> <ref>    pin a submodule to a tag, branch or commit
#        utils/update.sh --verify        fail if a submodule differs from versions.lock
#
# <name> is dataserver, stream-server, tinymce-clean-server or web-library.
# Pinning checks out <ref>, checks that the patches still apply, updates versions.lock and
# WEB_LIBRARY_COMMIT in .env, and stages the submodule pointer. Rebuild afterwards; the
# db-migrate service brings the database up to date on the next start.
set -e
cd "$(dirname "$0")/.."
LOCK=versions.lock

pinned() { awk -v p="$1" '$1 == p { print $3 }' "$LOCK"; }

if [ $# -eq 0 ]; then
	grep -v '^#' "$LOCK" | while read -r path ref commit; do
		[ -n "$path" ] || continue
		git -C "$path" fetch -q --tags origin
		latestTag=$(git -C "$path" tag --sort=-v:refname | grep -E '^v?[0-9]' | head -1)
		ahead=$(git -C "$path" rev-list --count "$commit..origin/HEAD")
		echo "$path: $ref ($(echo "$commit" | cut -c1-9)), upstream: ${latestTag:-no tags}, $ahead commits ahead on master"
	done
	exit 0
fi

if [ "$1" = "--verify" ]; then
	grep -v '^#' "$LOCK" | while read -r path ref commit; do
		[ -n "$path" ] || continue
		head=$(git -C "$path" rev-parse HEAD)
		[ "$head" = "$commit" ] || { echo "$path is at $head, versions.lock says $ref ($commit)" >&2; exit 1; }
	done
	echo "Submodules match versions.lock"
	exit 0
fi

name="$1" ref="$2"
path="src/server/$name"
[ -n "$ref" ] && [ -n "$(pinned "$path")" ] || { echo "Usage: $0 <name> <ref>" >&2; exit 1; }

git -C "$path" fetch -q --tags origin
commit=$(git -C "$path" rev-parse --verify "$ref^{commit}" 2>/dev/null \
	|| git -C "$path" rev-parse --verify "origin/$ref^{commit}")
git -C "$path" checkout -q "$commit"
git -C "$path" submodule update -q --init --recursive

# Tags keep their name; anything else is named by branch and commit date
if git -C "$path" rev-parse -q --verify "refs/tags/$ref" >/dev/null; then
	name_="$ref"
else
	name_="master@$(git -C "$path" log -1 --format=%cs "$commit")"
fi

[ "$name" = dataserver ] && ./utils/patch.sh --check

awk -v p="$path" -v r="$name_" -v c="$commit" \
	'$1 == p { printf "%-35s %-22s %s\n", p, r, c; next } { print }' "$LOCK" > "$LOCK.tmp"
mv "$LOCK.tmp" "$LOCK"
if [ "$name" = web-library ] && [ -e .env ]; then
	sed -i "s/^WEB_LIBRARY_COMMIT=.*/WEB_LIBRARY_COMMIT=$commit/" .env
fi
git add "$path" "$LOCK"

echo "Pinned $path to $name_ ($commit)"
echo "Rebuild with: docker compose build && docker compose up -d"
