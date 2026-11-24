#!/bin/bash
# Builds ScreenRest.app for macOS 13+ with only the Xcode Command Line Tools (no Xcode project).
#
#   ./mac/build.sh               universal app (Apple silicon + Intel) in mac/build/ScreenRest.app
#   ./mac/build.sh --package     also writes dist/ScreenRest-<version>-mac.dmg and .zip with SHA-256 checksums
#   ARCHS=arm64 ./mac/build.sh   one architecture only (faster while developing)
#   VERSION=1.2.0 ./mac/build.sh version number in the app and file names (CI passes it from the v* tag)
#
# Signing and notarization (optional; without them the app is signed ad hoc and Gatekeeper warns on first open):
#   SIGN_IDENTITY   "Developer ID Application: Your Name (TEAMID)"  (a certificate in your keychain);
#                   "-" signs ad hoc with the hardened runtime, to test what a notarized build will behave like
#   and, to notarize with --package, either
#   NOTARY_PROFILE  a keychain profile made once with:
#                   xcrun notarytool store-credentials screenrest --apple-id you@example.com --team-id TEAMID
#   or APPLE_ID, APPLE_TEAM_ID and APPLE_APP_PASSWORD (an app-specific password), as CI uses.
# See mac/README.md ("Signing and notarizing").
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
VERSION="${VERSION:-1.1.1}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
OUT="$HERE/build"
FINAL="$OUT/ScreenRest.app"
# Assemble and sign outside iCloud Drive: it keeps adding Finder metadata that codesign rejects.
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/screenrest-build.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/ScreenRest.app"
ARCHS="${ARCHS:-arm64 x86_64}"

mkdir -p "$OUT" "$APP/Contents/MacOS" "$APP/Contents/Resources/media"

echo "==> Compiling ($ARCHS)"
# Compile a snapshot of the sources: iCloud Drive can touch files mid-build ("modified during the build").
mkdir -p "$STAGE/src"
cp "$HERE"/Sources/*.swift "$STAGE/src/"
BINS=()
for arch in $ARCHS; do
    swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" \
        -o "$STAGE/ScreenRest-$arch" "$STAGE"/src/*.swift
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

xattr -cr "$APP"
TIMESTAMP=(--timestamp)
[[ "$SIGN_IDENTITY" == "-" ]] && TIMESTAMP=(--timestamp=none) # ad hoc signatures can't be timestamped
if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "==> Signing with $SIGN_IDENTITY (hardened runtime)"
    codesign --force --options runtime "${TIMESTAMP[@]}" \
        --entitlements "$HERE/ScreenRest.entitlements" --sign "$SIGN_IDENTITY" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
else
    echo "==> Signing (ad hoc; set SIGN_IDENTITY to sign with a Developer ID)"
    codesign --force --deep --sign - "$APP"
fi
rm -rf "$FINAL"
ditto "$APP" "$FINAL"

echo "Built $FINAL (version $VERSION)"

[[ "${1:-}" == "--package" ]] || exit 0

DIST="$ROOT/dist"
mkdir -p "$DIST"
ZIP="$DIST/ScreenRest-$VERSION-mac.zip"
DMG="$DIST/ScreenRest-$VERSION-mac.dmg"
rm -f "$ZIP" "$DMG"

echo "==> Disk image"
DMGDIR="$STAGE/dmg"
mkdir -p "$DMGDIR"
ditto "$APP" "$DMGDIR/ScreenRest.app"
ln -s /Applications "$DMGDIR/Applications"
hdiutil create -quiet -volname "ScreenRest" -srcfolder "$DMGDIR" -ov -format UDZO "$DMG"
if [[ -n "$SIGN_IDENTITY" ]]; then codesign --force "${TIMESTAMP[@]}" --sign "$SIGN_IDENTITY" "$DMG"; fi

# Notarize the disk image (this covers the app inside it), then staple the ticket to both,
# so Gatekeeper accepts them even offline.
NOTARY_ARGS=()
if [[ -n "$NOTARY_PROFILE" ]]; then
    NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    NOTARY_ARGS=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
fi
if [[ ${#NOTARY_ARGS[@]} -gt 0 ]]; then
    if [[ -z "$SIGN_IDENTITY" || "$SIGN_IDENTITY" == "-" ]]; then
        echo "Notarizing needs SIGN_IDENTITY set to a Developer ID certificate." >&2; exit 1
    fi
    echo "==> Notarizing (this usually takes a few minutes)"
    xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler staple "$APP"
    rm -rf "$FINAL" && ditto "$APP" "$FINAL"
    spctl --assess --type execute --verbose "$APP" || true
else
    echo "==> Not notarized (no notary credentials set)"
fi

echo "==> Zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> SHA-256"
shasum -a 256 "$ZIP" "$DMG"
