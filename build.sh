#!/bin/zsh
# Generate the Xcode project and build. Output: build/Build/Products/Debug/HeadOrbit.app
set -euo pipefail
cd "$(dirname "$0")"
xcodegen generate
if xcodebuild -project HeadOrbit.xcodeproj -scheme HeadOrbit -configuration Debug \
  -derivedDataPath build build 2>&1 | awk '/error:|warning:|BUILD/'; then
  :
else
  build_status=$?
  echo "xcodebuild failed (exit $build_status)." >&2
  exit "$build_status"
fi
echo "→ build/Build/Products/Debug/HeadOrbit.app"
