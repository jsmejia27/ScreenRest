#!/bin/bash
# Builds ScreenRest.app for macOS 13+ with only the Xcode Command Line Tools (no Xcode project).
#
#   ./mac/build.sh            universal app (Apple silicon + Intel) in mac/build/ScreenRest.app
#   ./mac/build.sh --package  also writes dist/ScreenRest-<version>-mac.zip and .dmg with SHA-256 checksums
#   ARCHS=arm64 ./mac/build.sh   one architecture only (faster while developing)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
VERSION="1.1.1"
OUT="$HERE/build"
FINAL="$OUT/ScreenRest.app"
# Assemble and sign outside iCloud Drive: it keeps adding Finder metadata that codesign rejects.
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/screenrest-build.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/ScreenRest.app"
ARCHS="${ARCHS:-arm64 x86_64}"

mkdir -p "$OUT" "$APP/Contents/MacOS" "$APP/Contents/Resources/media"

echo "==> Compiling ($ARCHS)"
BINS=()
for arch in $ARCHS; do
    swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" \
        -o "$STAGE/ScreenRest-$arch" "$HERE"/Sources/*.swift
    BINS+=("$STAGE/ScreenRest-$arch")
done
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/ScreenRest"
rm -f "${BINS[@]}"

sed "s/__VERSION__/$VERSION/g" "$HERE/Info.plist" > "$APP/Contents/Info.plist"

echo "==> Icon"
"$APP/Contents/MacOS/ScreenRest" --make-iconset "$STAGE/ScreenRest.iconset"
iconutil -c icns "$STAGE/ScreenRest.iconset" -o "$APP/Contents/Resources/ScreenRest.icns"

echo "==> Exercise videos and voice-overs"
shopt -s nullglob
for f in "$ROOT"/media/*.gif "$ROOT"/media/*.wav; do cp "$f" "$APP/Contents/Resources/media/"; done

echo "==> Signing (ad-hoc)"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
rm -rf "$FINAL"
ditto "$APP" "$FINAL"

echo "Built $FINAL"

if [[ "${1:-}" == "--package" ]]; then
    DIST="$ROOT/dist"
    mkdir -p "$DIST"
    ZIP="$DIST/ScreenRest-$VERSION-mac.zip"
    DMG="$DIST/ScreenRest-$VERSION-mac.dmg"
    rm -f "$ZIP" "$DMG"
    ditto -c -k --keepParent "$APP" "$ZIP"

    DMGDIR="$STAGE/dmg"
    mkdir -p "$DMGDIR"
    ditto "$APP" "$DMGDIR/ScreenRest.app"
    ln -s /Applications "$DMGDIR/Applications"
    hdiutil create -quiet -volname "ScreenRest" -srcfolder "$DMGDIR" -ov -format UDZO "$DMG"

    echo "==> SHA-256"
    shasum -a 256 "$ZIP" "$DMG"
fi
