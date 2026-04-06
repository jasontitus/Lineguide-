#!/usr/bin/env bash
# Generate App Store / README screenshots by driving the app through its
# core flows on the iPhone 17 Pro Max simulator.
#
# Usage:
#   scripts/generate_screenshots.sh
#
# Output:
#   build/screenshots/          — raw PNGs from the test run
#   fastlane/screenshots/en-US/ — copied with App Store naming
#
# Requirements:
#   - Xcode + iOS simulators installed
#   - Flutter integration_test set up (pubspec dev dep)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# iPhone 16 Pro Max has the same 6.9" display as iPhone 17 Pro Max but
# runs on x86_64 iOS 18.6 simulator, avoiding the arm64 compatibility
# issue with google_mlkit pods on iOS 26 simulators.
DEVICE_NAME="iPhone 16 Pro Max"
OUT_DIR="$REPO_ROOT/build/screenshots"
FASTLANE_DIR="$REPO_ROOT/fastlane/screenshots/en-US"

cd "$REPO_ROOT"

echo "==> Booting $DEVICE_NAME simulator..."
SIM_ID="$(xcrun simctl list devices available | grep -E "$DEVICE_NAME \(" | head -1 | grep -oE '[A-F0-9-]{36}')"
if [[ -z "$SIM_ID" ]]; then
  echo "ERROR: Could not find $DEVICE_NAME in available simulators."
  echo "Available simulators:"
  xcrun simctl list devices available | grep iPhone
  exit 1
fi

xcrun simctl boot "$SIM_ID" 2>/dev/null || true
open -a Simulator

# Wait for simulator to be ready
for _ in {1..30}; do
  if xcrun simctl list devices | grep "$SIM_ID" | grep -q Booted; then
    break
  fi
  sleep 1
done

echo "==> Pre-granting microphone + speech recognition permissions..."
xcrun simctl privacy "$SIM_ID" grant microphone com.tiltastech.castcircle 2>/dev/null || true
xcrun simctl privacy "$SIM_ID" grant speech-recognition com.tiltastech.castcircle 2>/dev/null || true

echo "==> Cleaning old screenshots..."
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "==> Running integration test..."
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshot_test.dart \
  -d "$SIM_ID"

echo "==> Copying screenshots to fastlane directory..."
mkdir -p "$FASTLANE_DIR"
# iPhone 17 Pro Max reports as 6.9" display for App Store Connect.
for src in "$OUT_DIR"/*.png; do
  [[ -e "$src" ]] || continue
  name="$(basename "$src")"
  cp "$src" "$FASTLANE_DIR/6.9_${name}"
done

echo ""
echo "✓ Screenshots generated:"
ls -1 "$OUT_DIR"
echo ""
echo "✓ Fastlane copies:"
ls -1 "$FASTLANE_DIR" | grep "^6.9_"
