#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_ARCH="${DANGO_ARCH:-$(uname -m)}"
PACKAGE_STAGE="$ROOT_DIR/.build/release-staging/$PACKAGE_ARCH"
OUTPUT_DIR="$ROOT_DIR/dist/releases"
VERSION="$(sed -n 's/^APP_VERSION="\([^"]*\)"/\1/p' "$ROOT_DIR/script/build_and_run.sh")"
DANGO_BUILD_ROOT="$ROOT_DIR/.build/release-build/$PACKAGE_ARCH" DANGO_DIST_DIR="$PACKAGE_STAGE" DANGO_CONFIGURATION=release DANGO_ARCH="$PACKAGE_ARCH" "$ROOT_DIR/script/build_and_run.sh" --build
APP_BUNDLE="$PACKAGE_STAGE/TomorrowPet.app"
if [[ -n "${MACOS_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$MACOS_SIGNING_IDENTITY" "$APP_BUNDLE"
fi
codesign --verify --deep --strict "$APP_BUNDLE"
plutil -lint "$APP_BUNDLE/Contents/Info.plist"
mkdir -p "$OUTPUT_DIR"
STEM="TomorrowPet-$VERSION-macOS-$PACKAGE_ARCH"
DMG_ROOT="$PACKAGE_STAGE/dmg"
mkdir -p "$DMG_ROOT"
ditto "$APP_BUNDLE" "$DMG_ROOT/TomorrowPet.app"
ln -sfn /Applications "$DMG_ROOT/Applications"
hdiutil create -volname "明日团子 $VERSION" -srcfolder "$DMG_ROOT" -ov -format UDZO "$OUTPUT_DIR/$STEM.dmg"
if [[ -n "${MACOS_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$OUTPUT_DIR/$STEM.dmg" --keychain-profile "$MACOS_NOTARY_PROFILE" --wait
  xcrun stapler staple "$OUTPUT_DIR/$STEM.dmg"
fi
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$OUTPUT_DIR/$STEM.zip"
(cd "$OUTPUT_DIR" && shasum -a 256 "$STEM.dmg" "$STEM.zip" > "$STEM.sha256")
echo "Packaged $OUTPUT_DIR/$STEM.dmg"
