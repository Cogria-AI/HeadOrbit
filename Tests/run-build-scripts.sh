#!/bin/bash
# Regression checks for the build wrappers. Xcode and DMG creation are mocked.
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/headorbit-build-tests.XXXXXX")
trap 'rm -rf "$test_root"' EXIT

mock_bin="$test_root/bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/xcodegen" <<'MOCK'
#!/bin/sh
exit 0
MOCK
cat > "$mock_bin/xcodebuild" <<'MOCK'
#!/bin/sh
printf '%s\n' "$HEADORBIT_TEST_BUILD_OUTPUT"
exit "$HEADORBIT_TEST_BUILD_EXIT"
MOCK
cat > "$mock_bin/hdiutil" <<'MOCK'
#!/bin/sh
touch "$HEADORBIT_TEST_PACKAGE_MARKER"
for output_path do :; done
printf 'mock dmg\n' > "$output_path"
MOCK
chmod +x "$mock_bin/"*

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

run_case() {
  local script=$1 build_exit=$2 build_output=$3 name=$4
  local case_dir="$test_root/$name"
  mkdir -p "$case_dir/build/Build/Products/Release/HeadOrbit.app/Contents" \
    "$case_dir/build/dmg" "$case_dir/dist"
  cp "$repo_root/$script" "$case_dir/$script"
  # A previous successful build must never be packaged after compilation fails.
  cat > "$case_dir/build/Build/Products/Release/HeadOrbit.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>0.0.0</string></dict></plist>
PLIST
  printf 'old staging\n' > "$case_dir/build/dmg/untouched"
  printf 'old dmg\n' > "$case_dir/dist/HeadOrbit-v0.0.0.dmg"
  local result=0
  PATH="$mock_bin:$PATH" \
    HEADORBIT_TEST_BUILD_EXIT="$build_exit" \
    HEADORBIT_TEST_BUILD_OUTPUT="$build_output" \
    HEADORBIT_TEST_PACKAGE_MARKER="$case_dir/packaged" \
    /bin/zsh "$case_dir/$script" > "$case_dir/output.log" 2>&1 || result=$?

  [[ $result -eq $build_exit ]] || fail "$name: expected exit $build_exit, got $result"
  local output
  output=$(cat "$case_dir/output.log")
  if [[ $build_exit -ne 0 ]]; then
    [[ $output == *"xcodebuild failed (exit $build_exit)."* ]] || fail "$name: missing failure message"
    [[ $output != *"→"* ]] || fail "$name: reported success after build failure"
    [[ ! -e "$case_dir/packaged" ]] || fail "$name: packaged a failed build"
    [[ -f "$case_dir/build/dmg/untouched" ]] || fail "$name: modified old staging"
    [[ $(cat "$case_dir/dist/HeadOrbit-v0.0.0.dmg") == "old dmg" ]] || fail "$name: modified old DMG"
  else
    [[ $output == *"→"* ]] || fail "$name: missing success message"
    if [[ $script == package.sh ]]; then
      [[ -f "$case_dir/packaged" ]] || fail "$name: did not invoke mocked packaging"
      [[ $(cat "$case_dir/dist/HeadOrbit-v0.0.0.dmg") == "mock dmg" ]] || fail "$name: missing mocked DMG"
    fi
  fi
  echo "PASS: $name"
}

run_case build.sh 65 'error: simulated compilation failure' debug_failure
run_case package.sh 65 'error: simulated compilation failure' release_failure_keeps_stale_artifacts
# A successful build with no matching log lines must not fail due to its filter.
run_case build.sh 0 'ordinary compiler output' debug_success_without_filtered_output
run_case package.sh 0 'ordinary compiler output' release_success_without_filtered_output
