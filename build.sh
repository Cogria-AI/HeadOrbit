#!/bin/zsh
# Generate the Xcode project and build. Output: build/Build/Products/Debug/HeadOrbit.app
set -euo pipefail
cd "$(dirname "$0")"
xcodegen generate
xcodebuild -project HeadOrbit.xcodeproj -scheme HeadOrbit -configuration Debug \
  -derivedDataPath build build 2>&1 | grep -E "error:|warning:|BUILD" || true
echo "→ build/Build/Products/Debug/HeadOrbit.app"
