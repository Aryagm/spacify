#!/usr/bin/env bash
set -euo pipefail

SPOTIFY_APP="${SPOTIFY_APP:-/Applications/Spotify.app}"
SPOTIFY_BIN="$SPOTIFY_APP/Contents/MacOS/Spotify"
CEF_FRAMEWORK="$SPOTIFY_APP/Contents/Frameworks/Chromium Embedded Framework.framework/Versions/A/Chromium Embedded Framework"

if [[ ! -d "$SPOTIFY_APP" ]]; then
  echo "Spotify app not found: $SPOTIFY_APP" >&2
  exit 1
fi

echo "== Spotify bundle =="
plutil -p "$SPOTIFY_APP/Contents/Info.plist" \
  | rg 'CFBundleIdentifier|CFBundleShortVersionString|CFBundleVersion|NSPrincipalClass' || true

echo
echo "== Running Spotify processes =="
pgrep -afil 'Spotify|Chromium Embedded Framework|Spotify Helper' || true

echo
echo "== Main process linked Apple audio/web frameworks =="
otool -L "$SPOTIFY_BIN" \
  | rg 'Chromium Embedded Framework|AVFoundation|AVFAudio|AudioToolbox|AudioUnit|CoreAudio|CoreMedia|WebKit' || true

echo
echo "== CEF framework version/signals =="
otool -L "$CEF_FRAMEWORK" | head -n 3
strings -a "$CEF_FRAMEWORK" \
  | rg 'MacAVFoundationPlayback|AVFoundationOutputStream|AVSampleBufferAudioRenderer|Spatial Audio|AUHALStream|AudioManagerMac' || true

echo
echo "== Main Spotify playback signals =="
strings -a "$SPOTIFY_BIN" \
  | rg -i 'AVFoundationRenderer|core-playback|playback_esperanto|SPTPlaybackSettings|AudioUnit|CoreAudio|AudioOutput' \
  | head -n 80 || true

if command -v make >/dev/null && [[ -f Makefile ]]; then
  echo
  echo "== CoreAudio process tap view =="
  make list || true
fi

echo
echo "== Signature summary =="
codesign -dv --verbose=4 "$SPOTIFY_APP" 2>&1 \
  | rg 'Identifier|flags|Authority|TeamIdentifier|Sealed Resources|Runtime' || true

