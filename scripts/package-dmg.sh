#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

version=$(./version.sh)
mkdir -p build
work=$(mktemp -d build/.therm2-dmg.XXXXXX)
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM

app=build/Therm2.app
binary="$app/Contents/MacOS/Therm2"
# Multi-architecture SwiftPM builds use Xcode's build system, which fails to
# resolve SwiftTermBuildInfoPlugin. Build each slice with native SwiftPM instead.
for arch in arm64 x86_64; do
    ./scripts/build.sh release --build-system native --arch "$arch"
    cp "$binary" "$work/Therm2-$arch"
done
lipo -create "$work/Therm2-arm64" "$work/Therm2-x86_64" -output "$work/Therm2"
mv -f "$work/Therm2" "$binary"
for arch in arm64 x86_64; do
    lipo "$binary" -verify_arch "$arch"
done
codesign --force --sign - "$app"
codesign --verify --strict "$app"

mkdir "$work/staging"
ditto "$app" "$work/staging/Therm2.app"
ln -s /Applications "$work/staging/Applications"

name="Therm2-$version-universal.dmg"
hdiutil create -volname "Therm2 $version" -srcfolder "$work/staging" \
    -fs HFS+ -format UDZO "$work/$name"
hdiutil verify "$work/$name"
(
    cd "$work"
    shasum -a 256 "$name" > "$name.sha256"
)
mv -f "$work/$name" "build/$name"
mv -f "$work/$name.sha256" "build/$name.sha256"
printf '%s\n' "build/$name" "build/$name.sha256"
