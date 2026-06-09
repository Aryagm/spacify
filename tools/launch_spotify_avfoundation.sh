#!/usr/bin/env bash
set -euo pipefail

SPOTIFY_APP="${SPOTIFY_APP:-/Applications/Spotify.app}"

if [[ ! -d "$SPOTIFY_APP" ]]; then
  echo "Spotify app not found: $SPOTIFY_APP" >&2
  exit 1
fi

echo "Quitting Spotify if it is running..."
osascript -e 'tell application "Spotify" to quit' >/dev/null 2>&1 || true
sleep 3

echo "Launching Spotify with Chromium AVFoundation playback enabled..."
open "$SPOTIFY_APP" --args \
  --enable-features=MacAVFoundationPlayback \
  --enable-logging=stderr \
  --v=1 \
  '--vmodule=*audio*=2,*audio_manager_mac*=2,*avfoundation_output_stream*=2'

sleep 5

echo
echo "Spotify process tree:"
ps -axo pid,ppid,command | rg '/Applications/Spotify.app|Spotify Helper' || true

echo
echo "Feature-flag check:"
ps -axo pid,command | rg 'Spotify|Spotify Helper' | rg 'MacAVFoundationPlayback|--disable-features' || true

echo
echo "Now play a Spotify track and check the AirPods menu in Control Center."
echo "If Spatial Audio / Spatialize Stereo exposes Fixed or Head Tracked, the runtime flag is enough."
