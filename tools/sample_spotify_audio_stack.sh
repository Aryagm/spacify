#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${LOG_DIR:-logs}"
DURATION="${DURATION:-5}"

spotify_pid="${1:-}"

if [[ -z "$spotify_pid" ]]; then
  spotify_pid="$(pgrep -x Spotify | head -n 1 || true)"
fi

if [[ -z "$spotify_pid" ]]; then
  echo "Spotify is not running." >&2
  exit 1
fi

mkdir -p "$LOG_DIR"

sample_file="$LOG_DIR/spotify-sample-$(date +%Y%m%d-%H%M%S).txt"

echo "Sampling Spotify pid $spotify_pid for ${DURATION}s..."
sample "$spotify_pid" "$DURATION" -file "$sample_file"

echo
echo "Sample: $sample_file"
echo
echo "Audio stack signals:"
rg -n -i \
  'CoreAudioDriver|Media Mixer Renderer|com\.apple\.audio\.IOThread|AVFoundationRenderer|AudioUnit2Renderer|CoreAudioRenderer|AVFoundationOutputStream|AUHALStream|AVSampleBufferAudioRenderer|AudioConverterFillComplexBuffer' \
  "$sample_file" || true

