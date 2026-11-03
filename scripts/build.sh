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
./scripts/generate-icons.sh --if-needed
# Recreate the bundle to invalidate macOS's icon cache, without cleaning SwiftPM.
mkdir -p build
bundle_work=$(mktemp -d build/.therm2-app.XXXXXX)
trap 'rm -rf "$bundle_work"' EXIT
trap 'exit 1' HUP INT TERM
app="$bundle_work/Therm2.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp build/icons/AppIcon.icns build/icons/Assets.car "$app/Contents/Resources/"
binary="$app/Contents/MacOS/Therm2"
cp "$bin_dir/Therm2" "$binary.tmp"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp COPYING "$app/Contents/Resources/COPYING"
cp Resources/SwiftTerm-LICENSE "$app/Contents/Resources/SwiftTerm-LICENSE"
mkdir -p "$app/Contents/Resources/Fonts"
cp Resources/Fonts/* "$app/Contents/Resources/Fonts/"
if [ "$configuration" = release ]; then
    strip -x "$binary.tmp"
fi
mv -f "$binary.tmp" "$binary"
codesign --force --sign - "$app"
if [ -e build/Therm2.app ]; then mv build/Therm2.app "$bundle_work/previous.app"; fi
if ! mv "$app" build/Therm2.app; then
    if [ -d "$bundle_work/previous.app" ]; then mv "$bundle_work/previous.app" build/Therm2.app; fi
    exit 1
fi
touch build/Therm2.app
echo build/Therm2.app
