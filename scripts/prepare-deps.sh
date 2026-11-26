#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
scratch=${THERM2_BUILD_PATH:-.build}
swift package --scratch-path "$scratch" resolve "$@"
checkout="$scratch/checkouts/SwiftTerm"
expected=b30669619244453a66b14a6b10ec859e3016d6fd
if [ "$(git -C "$checkout" rev-parse HEAD)" != "$expected" ]; then
    echo 'SwiftTerm revision changed; review the dependency patches before building.' >&2
    exit 1
fi
patches="horizontal-scroll foreground-brightness unlimited-scrollback local-links link-cursor
    horizontal-scroll-review style-arena-reclamation mouse-pointer-shapes local-link-policy"

# Later patches can change earlier hunks. Recreate the successive trees in a
# temporary index and find the last one already present in the checkout.
index_dir=$(mktemp -d "${TMPDIR:-/tmp}/therm2-swiftterm-index.XXXXXX")
trap 'rm -rf "$index_dir"' EXIT
trap 'exit 1' HUP INT TERM
export GIT_INDEX_FILE="$index_dir/index"
git -C "$checkout" read-tree "$expected"
applied=
if git -C "$checkout" diff --quiet; then applied=$expected; fi
for name in $patches; do
    patch="$PWD/patches/swiftterm-$name.patch"
    git -C "$checkout" apply --cached "$patch"
    if git -C "$checkout" diff --quiet; then
        applied=$(git -C "$checkout" write-tree)
    fi
done
if [ -z "$applied" ]; then
    echo 'SwiftTerm checkout differs from the dependency patch stack.' >&2
    exit 1
fi

# Apply the remaining changes together so conflicts leave the checkout intact.
patched=$(git -C "$checkout" write-tree)
if [ "$applied" != "$patched" ]; then
    git -C "$checkout" diff --binary --no-ext-diff --no-textconv --no-color --src-prefix=a/ --dst-prefix=b/ \
        "$applied" "$patched" > "$index_dir/remaining.patch"
    git -C "$checkout" apply "$index_dir/remaining.patch"
fi
