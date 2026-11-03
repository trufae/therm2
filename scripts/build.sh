#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
configuration=${1:-release}
case "$configuration" in debug|release) ;; *) echo 'usage: scripts/build.sh [debug|release]' >&2; exit 2 ;; esac
if [ "$#" -gt 0 ]; then shift; fi
./scripts/prepare-deps.sh "$@"
scratch=${THERM2_BUILD_PATH:-.build}
swift build --scratch-path "$scratch" --configuration "$configuration" --product Therm2 "$@"
bin_dir=$(swift build --scratch-path "$scratch" --configuration "$configuration" --show-bin-path "$@")
app=build/Therm2.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
binary="$app/Contents/MacOS/Therm2"
cp "$bin_dir/Therm2" "$binary.tmp"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp COPYING "$app/Contents/Resources/COPYING"
cp Resources/SwiftTerm-LICENSE "$app/Contents/Resources/SwiftTerm-LICENSE"
if [ "$configuration" = release ]; then
    strip -x "$binary.tmp"
fi
mv -f "$binary.tmp" "$binary"
codesign --force --sign - "$app"
echo "$app"
