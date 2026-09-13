#!/bin/zsh
# Build the Release app and wrap it in a DMG. Output: dist/HeadOrbit-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")"
xcodegen generate
xcodebuild -project HeadOrbit.xcodeproj -scheme HeadOrbit -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY=- build 2>&1 | grep -E "error:|BUILD" || true
APP=build/Build/Products/Release/HeadOrbit.app
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
STAGE=build/dmg
rm -rf "$STAGE" && mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="dist/HeadOrbit-v${VERSION}.dmg"
rm -f "$DMG"
hdiutil create -volname "HeadOrbit" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
echo "→ $DMG"
