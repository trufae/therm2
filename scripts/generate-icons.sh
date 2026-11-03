#!/bin/sh
# Compile SVG artwork using Therm2's Icon Composer background and styling.
set -eu

usage() {
    echo "usage: $0 [--if-needed] [source.svg [output-directory]]"
    echo "Defaults: Resources/AppIcon.icon/Assets/prompt.svg and build/icons"
}
if_needed=false
if [ "${1:-}" = --if-needed ]; then if_needed=true; shift; fi
case "${1:-}" in -h|--help) usage; exit 0 ;; esac
if [ "$#" -gt 2 ]; then usage >&2; exit 2; fi

root=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
svg=${1:-"$root/Resources/AppIcon.icon/Assets/prompt.svg"}
output=${2:-"$root/build/icons"}
case "$svg" in /*) ;; *) svg="$PWD/$svg" ;; esac
case "$output" in /*) ;; *) output="$PWD/$output" ;; esac
if [ ! -f "$svg" ]; then
    echo "SVG source not found: $svg" >&2
    exit 1
fi
for tool in xcrun iconutil; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Missing $tool; run this script on macOS with Xcode installed." >&2
        exit 1
    fi
done

# Hash file contents so an edit is detected even when timestamps are preserved.
fingerprint=$({
    cat "$root/scripts/generate-icons.sh" "$root/Resources/AppIcon.icon/icon.json" \
        "$root/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json" "$svg"
    xcodebuild -version
} | shasum -a 256 | cut -d ' ' -f 1)
if [ "$if_needed" = true ] && [ -f "$output/.source-hash" ] && \
    [ "$(cat "$output/.source-hash")" = "$fingerprint" ] && \
    [ -s "$output/AppIcon.icns" ] && [ -s "$output/Assets.car" ]; then
    echo "Icon exports are up to date in $output"
    exit 0
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/therm2-icons.XXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
cp -R "$root/Resources/AppIcon.icon" "$work/AppIcon.icon"
cp "$svg" "$work/AppIcon.icon/Assets/prompt.svg"
mkdir -p "$work/compiled"
# "all" includes the high-resolution ICNS images otherwise kept only in Assets.car.
if ! xcrun actool "$work/AppIcon.icon" --compile "$work/compiled" \
    --platform macosx --minimum-deployment-target 13.0 --target-device mac \
    --app-icon AppIcon --standalone-icon-behavior all \
    --output-partial-info-plist "$work/compiled/icon-info.plist" \
    --output-format human-readable-text --warnings --errors > "$work/actool.log" 2>&1; then
    cat "$work/actool.log" >&2
    exit 1
fi
iconutil --convert iconset --output "$work/AppIcon.iconset" "$work/compiled/AppIcon.icns"

catalog="$work/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$catalog"
cp "$root/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json" "$catalog/Contents.json"
while read -r source destination; do
    cp "$work/AppIcon.iconset/$source" "$catalog/$destination"
done <<'ICONS'
icon_16x16.png Icon-16.png
icon_16x16@2x.png Icon-32.png
icon_32x32.png Icon-33.png
icon_32x32@2x.png Icon-64.png
icon_128x128.png Icon-128.png
icon_128x128@2x.png Icon-256.png
icon_256x256.png Icon-257.png
icon_256x256@2x.png Icon-513.png
icon_512x512.png Icon-512.png
icon_512x512@2x.png Icon-1024.png
ICONS

mkdir -p "$output"
cp "$work/compiled/AppIcon.icns" "$work/compiled/Assets.car" "$work/compiled/icon-info.plist" "$output/"
cp -R "$work/AppIcon.icon" "$work/AppIcon.iconset" "$work/Assets.xcassets" "$output/"
printf '%s\n' "$fingerprint" > "$output/.source-hash"
echo "Generated AppIcon.icon, AppIcon.icns, Assets.car, AppIcon.iconset, and Assets.xcassets in $output"
