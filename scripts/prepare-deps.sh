#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
scratch=${THERM2_BUILD_PATH:-.build}
swift package --scratch-path "$scratch" resolve "$@"
checkout="$scratch/checkouts/SwiftTerm"
expected=a183c15b52858530a17de57dcc72b93eeebc9857
if [ "$(git -C "$checkout" rev-parse HEAD)" != "$expected" ]; then
    echo 'SwiftTerm revision changed; review the dependency patches before building.' >&2
    exit 1
fi
for patch in "$PWD/patches/swiftterm-horizontal-scroll.patch" "$PWD/patches/swiftterm-foreground-brightness.patch" "$PWD/patches/swiftterm-unlimited-scrollback.patch"; do
    if git -C "$checkout" apply --reverse --check "$patch" 2>/dev/null; then
        continue
    fi
    git -C "$checkout" apply --check "$patch"
    git -C "$checkout" apply "$patch"
done
