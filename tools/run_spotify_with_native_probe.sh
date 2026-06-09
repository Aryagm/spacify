#!/usr/bin/env bash
set -euo pipefail

SPOTIFY_APP="${SPOTIFY_APP:-/Applications/Spotify.app}"
SPOTIFY_BIN="$SPOTIFY_APP/Contents/MacOS/Spotify"
LOG_DIR="${LOG_DIR:-logs}"

if [[ ! -x "$SPOTIFY_BIN" ]]; then
  echo "Spotify executable not found: $SPOTIFY_BIN" >&2
  exit 1
fi

mkdir -p "$LOG_DIR"

probe_dylib="$(tools/build_native_audio_probe.sh)"
probe_log="$LOG_DIR/spotify-native-audio-probe-$(date +%Y%m%d-%H%M%S).log"
stdout_log="$LOG_DIR/spotify-native-audio-probe-stdout-$(date +%Y%m%d-%H%M%S).log"

echo "Probe dylib: $probe_dylib"
echo "Probe log: $probe_log"
echo
echo "Spotify code-signing entitlements relevant to injection:"
codesign -d --entitlements :- "$SPOTIFY_APP" 2>/dev/null \
  | plutil -p - 2>/dev/null \
  | rg 'allow-dyld|disable-library|allow-jit|unsigned|page-protection' || true

echo
echo "Quitting Spotify if it is running..."
osascript -e 'tell application "Spotify" to quit' >/dev/null 2>&1 || true
sleep 3

echo "Launching Spotify with DYLD interpose probe..."
SPOTIFY_NATIVE_AUDIO_PROBE_LOG="$probe_log" \
DYLD_INSERT_LIBRARIES="$PWD/$probe_dylib" \
nohup "$SPOTIFY_BIN" >"$stdout_log" 2>&1 &

spotify_pid=$!
sleep 5

echo "Spotify PID: $spotify_pid"

echo
echo "Probe load check:"
if [[ -f "$probe_log" ]] && rg -q 'native audio probe loaded' "$probe_log"; then
  rg -n 'native audio probe loaded|AudioComponentInstanceNew|AudioUnitSetProperty|AudioOutputUnitStart' "$probe_log" || true
else
  echo "Probe did not load. Hardened runtime likely ignored DYLD_INSERT_LIBRARIES."
  echo "Stdout/stderr log: $stdout_log"
fi

echo
echo "If the probe loaded, play Spotify for 10-20 seconds and run:"
echo "  rg -n 'AudioComponentInstanceNew|AudioUnitSetProperty|AudioOutputUnitStart|AudioObjectSetPropertyData' '$probe_log'"

