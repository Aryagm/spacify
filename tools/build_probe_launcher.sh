#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUT_DIR:-build/native-audio-probe}"
OUT_BIN="$OUT_DIR/spotify_probe_launcher"

mkdir -p "$OUT_DIR"

xcrun clang \
  -O2 \
  -Wall \
  -Wextra \
  tools/spotify_probe_launcher.c \
  -o "$OUT_BIN"

codesign --force --sign - "$OUT_BIN" >/dev/null

echo "$OUT_BIN"

