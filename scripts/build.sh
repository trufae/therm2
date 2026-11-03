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
xcrun actool Resources/Assets.xcassets --compile "$app/Contents/Resources" \
    --platform macosx --minimum-deployment-target 13.0 --target-device mac \
    --app-icon AppIcon --output-partial-info-plist "$scratch/icon-info.plist" \
    --output-format human-readable-text --warnings --errors > "$scratch/icon-build.log" 2>&1 || {
    cat "$scratch/icon-build.log" >&2
    exit 1
}
binary="$app/Contents/MacOS/Therm2"
cp "$bin_dir/Therm2" "$binary.tmp"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cp COPYING "$app/Contents/Resources/COPYING"
cp Resources/SwiftTerm-LICENSE "$app/Contents/Resources/SwiftTerm-LICENSE"
mkdir -p "$app/Contents/Resources/Fonts"
cp Resources/Fonts/* "$app/Contents/Resources/Fonts/"
if [ "$configuration" = release ]; then
    strip -x "$binary.tmp"
fi
mv -f "$binary.tmp" "$binary"
codesign --force --sign - "$app"
echo "$app"
