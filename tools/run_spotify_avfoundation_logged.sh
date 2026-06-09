#!/usr/bin/env bash
set -euo pipefail

SPOTIFY_APP="${SPOTIFY_APP:-/Applications/Spotify.app}"
SPOTIFY_BIN="$SPOTIFY_APP/Contents/MacOS/Spotify"
LOG_DIR="${LOG_DIR:-logs}"
LOG_FILE="${LOG_FILE:-$LOG_DIR/spotify-avfoundation-$(date +%Y%m%d-%H%M%S).log}"

if [[ ! -x "$SPOTIFY_BIN" ]]; then
  echo "Spotify executable not found: $SPOTIFY_BIN" >&2
  exit 1
fi

mkdir -p "$LOG_DIR"

echo "Quitting Spotify if it is running..."
osascript -e 'tell application "Spotify" to quit' >/dev/null 2>&1 || true
sleep 3

echo "Launching Spotify executable directly with Chromium AVFoundation playback enabled."
echo "Log: $LOG_FILE"

nohup "$SPOTIFY_BIN" \
  --enable-features=MacAVFoundationPlayback \
  --enable-logging=stderr \
  --v=2 \
  '--vmodule=*audio*=3,*audio_manager_mac*=3,*avfoundation_output_stream*=3' \
  >"$LOG_FILE" 2>&1 &

spotify_pid=$!

sleep 5

echo
echo "Spotify PID: $spotify_pid"
echo
echo "Feature-flag check:"
ps -axo pid,command | rg 'Spotify|Spotify Helper' | rg 'MacAVFoundationPlayback|--disable-features' || true

echo
echo "Initial AVFoundation/AUHAL log scan:"
rg -i 'AVFoundationOutputStream|AVSampleBufferAudioRenderer|Creating AVFoundationOutputStream|AUHALStream|MacAVFoundationPlayback' "$LOG_FILE" || true

echo
echo "Play a Spotify track for 10-20 seconds, then run:"
echo "  rg -i 'AVFoundationOutputStream|AVSampleBufferAudioRenderer|Creating AVFoundationOutputStream|AUHALStream' '$LOG_FILE'"

