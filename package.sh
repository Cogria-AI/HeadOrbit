#!/bin/zsh
# Build the Release app and wrap it in a DMG. Output: dist/HeadOrbit-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")"
xcodegen generate
if xcodebuild -project HeadOrbit.xcodeproj -scheme HeadOrbit -configuration Release \
  -derivedDataPath build CODE_SIGN_IDENTITY=- build 2>&1 | awk '/error:|BUILD/'; then
  :
else
  build_status=$?
  echo "xcodebuild failed (exit $build_status)." >&2
  exit "$build_status"
fi
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
