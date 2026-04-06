#!/usr/bin/env bash
# Generate an animated webp of the rehearsal cue-practice flow by running
# the rehearsal demo integration test while recording the simulator screen.
#
# Output: build/screenshots/rehearsal_demo.webp
#
# Requirements:
#   - Xcode iOS simulator with iPhone 16 Pro Max (6.9" display)
#   - ffmpeg (brew install ffmpeg)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEVICE_NAME="iPhone 16 Pro Max"
OUT_DIR="$REPO_ROOT/build/screenshots"
MOV_PATH="$OUT_DIR/rehearsal_demo.mov"
WEBP_PATH="$OUT_DIR/rehearsal_demo.webp"

cd "$REPO_ROOT"

echo "==> Finding $DEVICE_NAME simulator..."
SIM_ID="$(xcrun simctl list devices available | grep -E "$DEVICE_NAME \(" | head -1 | grep -oE '[A-F0-9-]{36}')"
if [[ -z "$SIM_ID" ]]; then
  echo "ERROR: Could not find $DEVICE_NAME"
  exit 1
fi

echo "==> Booting simulator..."
xcrun simctl boot "$SIM_ID" 2>/dev/null || true
open -a Simulator

for _ in {1..30}; do
  if xcrun simctl list devices | grep "$SIM_ID" | grep -q Booted; then
    break
  fi
  sleep 1
done

echo "==> Pre-granting microphone + speech recognition permissions..."
# Avoid the iOS permission dialogs blocking the recording by granting them
# up front. Safe to run even if the app isn't installed yet.
xcrun simctl privacy "$SIM_ID" grant microphone com.tiltastech.castcircle 2>/dev/null || true
xcrun simctl privacy "$SIM_ID" grant speech-recognition com.tiltastech.castcircle 2>/dev/null || true

mkdir -p "$OUT_DIR"
rm -f "$MOV_PATH" "$WEBP_PATH"

echo "==> Starting screen recording in background..."
xcrun simctl io "$SIM_ID" recordVideo --codec=h264 --force "$MOV_PATH" &
RECORD_PID=$!

# Give the recorder a moment to spin up before launching the test.
sleep 2

echo "==> Running rehearsal demo integration test..."
# Use `|| true` so we don't exit early if the test runner reports non-zero
# (some pumpAndSettle timeouts aren't fatal). We check the video file after.
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/rehearsal_demo_test.dart \
  -d "$SIM_ID" || true

echo "==> Stopping recording..."
# simctl recordVideo responds to SIGINT by flushing and finalizing the file.
kill -INT "$RECORD_PID" 2>/dev/null || true
wait "$RECORD_PID" 2>/dev/null || true

if [[ ! -f "$MOV_PATH" ]]; then
  echo "ERROR: no recording produced at $MOV_PATH"
  exit 1
fi

echo "==> Converting to animated webp (trimmed to rehearsal window)..."
# This ffmpeg doesn't include libwebp, so we go mov → optimized gif → webp.
# Recording captures the full build/install/launch cycle plus a few seconds
# of app-exit wind-down at the end. The actual rehearsal plays in the last
# ~45 seconds (36s wait loop + navigation), so we trim a 36s window ending
# ~7s before the video ends. Use the untouched MOV_PATH for manual clipping.
GIF_PATH="$OUT_DIR/rehearsal_demo.gif"
PALETTE_PATH="$OUT_DIR/_palette.png"
WINDOW=36
TRAILING_PAD=7  # seconds before video end to leave untouched

DURATION="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$MOV_PATH")"
START="$(awk "BEGIN { printf \"%.2f\", $DURATION - $WINDOW - $TRAILING_PAD }")"
echo "    mov duration: ${DURATION}s, trimming ${WINDOW}s starting at ${START}s"

ffmpeg -y -ss "$START" -t "$WINDOW" -i "$MOV_PATH" \
  -vf "fps=12,scale=540:-1:flags=lanczos,palettegen=max_colors=128" \
  "$PALETTE_PATH" 2>&1 | tail -3

ffmpeg -y -ss "$START" -t "$WINDOW" -i "$MOV_PATH" -i "$PALETTE_PATH" \
  -lavfi "fps=12,scale=540:-1:flags=lanczos [v]; [v][1:v] paletteuse=dither=bayer:bayer_scale=5" \
  "$GIF_PATH" 2>&1 | tail -3

rm -f "$PALETTE_PATH"

echo "==> Converting gif → animated webp..."
gif2webp -q 75 -m 6 -mt "$GIF_PATH" -o "$WEBP_PATH" 2>&1 | tail -3

# Keep the source mov for other clips.
echo "    keeping source mov at: $MOV_PATH"

if [[ -f "$WEBP_PATH" ]]; then
  SIZE="$(du -h "$WEBP_PATH" | cut -f1)"
  echo ""
  echo "✓ Generated $WEBP_PATH ($SIZE)"
else
  echo "ERROR: webp conversion failed"
  exit 1
fi
