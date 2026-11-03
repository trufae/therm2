#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
plist="$root/Resources/Info.plist"
plistbuddy=/usr/libexec/PlistBuddy

if [ "$#" -gt 1 ]; then
    echo 'usage: version.sh [X.Y.Z]' >&2
    exit 2
fi
current_version=$("$plistbuddy" -c 'Print :CFBundleShortVersionString' "$plist")
if [ "$#" -eq 0 ]; then
    printf '%s\n' "$current_version"
    exit 0
fi

new_version=$1
if ! printf '%s\n' "$new_version" | awk 'NR != 1 || !/^[0-9]+\.[0-9]+\.[0-9]+$/ { exit 1 }'; then
    echo "version.sh: expected version in the form X.Y.Z, got: $new_version" >&2
    exit 1
fi
if [ "$new_version" = "$current_version" ]; then
    printf 'version: %s (unchanged)\n' "$current_version"
    exit 0
fi
current_build=$("$plistbuddy" -c 'Print :CFBundleVersion' "$plist")
if ! printf '%s\n' "$current_build" | awk 'NR != 1 || !/^(0|[1-9][0-9]*)$/ { exit 1 }'; then
    echo "version.sh: expected an integer build number, got: $current_build" >&2
    exit 1
fi
new_build=$((current_build + 1))

# Replace both values together, leaving the original untouched on failure.
work=$(mktemp "$root/Resources/.Info.plist.XXXXXX")
trap 'rm -f "$work"' EXIT
trap 'exit 1' HUP INT TERM
cp -p "$plist" "$work"
"$plistbuddy" -c "Set :CFBundleShortVersionString $new_version" "$work"
"$plistbuddy" -c "Set :CFBundleVersion $new_build" "$work"
plutil -lint "$work" >/dev/null
mv -f "$work" "$plist"
printf 'version: %s -> %s\n' "$current_version" "$new_version"
printf 'build:   %s -> %s\n' "$current_build" "$new_build"
