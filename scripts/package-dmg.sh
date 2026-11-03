#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

version=$(./version.sh)
./scripts/build.sh release --arch arm64 --arch x86_64
app=build/Therm2.app
binary="$app/Contents/MacOS/Therm2"
for arch in arm64 x86_64; do
    lipo "$binary" -verify_arch "$arch"
done
codesign --verify --strict "$app"

work=$(mktemp -d build/.therm2-dmg.XXXXXX)
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
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
