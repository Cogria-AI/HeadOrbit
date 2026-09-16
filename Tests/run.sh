#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
test_build=$(mktemp -d)
trap 'rm -rf "$test_build"' EXIT
swiftc -module-cache-path "$test_build/cache" \
  HeadOrbit/Actions/DwellTrigger.swift \
  HeadOrbit/Actions/PostureReminderAction.swift \
  HeadOrbit/Actions/HeadAction.swift \
  HeadOrbit/Motion/HeadPose.swift \
  Tests/Stubs.swift Tests/main.swift -o "$test_build/tests"
"$test_build/tests"
