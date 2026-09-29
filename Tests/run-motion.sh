#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_binary=$(mktemp /tmp/headorbit-motion.XXXXXX)
trap 'rm -f "$test_binary"' EXIT
swiftc HeadOrbit/Motion/*.swift HeadOrbit/Actions/*.swift HeadOrbit/Overlay/*.swift HeadOrbit/UI/L10n.swift Tests/Motion/main.swift -o "$test_binary"
"$test_binary"
