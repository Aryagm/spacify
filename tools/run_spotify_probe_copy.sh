#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${LOG_DIR:-logs}"
PROBE_MODE="${PROBE_MODE:-load}"
mkdir -p "$LOG_DIR"

if [[ "$PROBE_MODE" == "component" || "$PROBE_MODE" == "audio" ]] &&
   [[ "${ALLOW_UNSAFE_COMPONENT_PROBE:-0}" != "1" ]]; then
  echo "Refusing PROBE_MODE=$PROBE_MODE because the AudioComponentInstanceNew interpose recurses in Spotify." >&2
  echo "Use PROBE_MODE=unit or PROBE_MODE=object. To reproduce the old crash-prone path, set ALLOW_UNSAFE_COMPONENT_PROBE=1." >&2
  exit 2
fi

probe_dylib="$(tools/build_native_audio_probe.sh)"
probe_launcher="$(tools/build_probe_launcher.sh)"
probe_app="$(tools/prepare_spotify_probe_copy.sh)"
probe_bin="$probe_app/Contents/MacOS/Spotify"

if [[ ! -x "$probe_bin" ]]; then
  echo "Instrumented Spotify executable not found: $probe_bin" >&2
  exit 1
fi

probe_log="$LOG_DIR/spotify-probe-copy-native-audio-$(date +%Y%m%d-%H%M%S).log"
stdout_log="$LOG_DIR/spotify-probe-copy-stdout-$(date +%Y%m%d-%H%M%S).log"

echo "Instrumented app: $probe_app"
echo "Probe mode: $PROBE_MODE"
echo "Probe dylib: $probe_dylib"
echo "Probe launcher: $probe_launcher"
echo "Probe log: $probe_log"

echo
echo "Instrumented app entitlements:"
codesign -d --entitlements :- "$probe_app" 2>/dev/null \
  | plutil -p - 2>/dev/null \
  | rg 'allow-dyld|disable-library|allow-jit|unsigned|page-protection' || true

echo
echo "Quitting Spotify if it is running..."
osascript -e 'tell application "Spotify" to quit' >/dev/null 2>&1 || true
pkill -TERM -f "$PWD/build/SpotifyNativeProbe.app/Contents/MacOS/Spotify" >/dev/null 2>&1 || true
pkill -TERM -f "$PWD/build/SpotifyNativeProbe.app/Contents/Frameworks/Spotify Helper" >/dev/null 2>&1 || true
sleep 3
pkill -KILL -f "$PWD/build/SpotifyNativeProbe.app/Contents/MacOS/Spotify" >/dev/null 2>&1 || true
pkill -KILL -f "$PWD/build/SpotifyNativeProbe.app/Contents/Frameworks/Spotify Helper" >/dev/null 2>&1 || true

echo "Launching copied Spotify with native audio probe..."
SPOTIFY_NATIVE_AUDIO_PROBE_LOG="$PWD/$probe_log" \
DYLD_INSERT_LIBRARIES="$PWD/$probe_dylib" \
"$PWD/$probe_launcher" "$PWD/$probe_bin" >"$stdout_log" 2>&1 </dev/null &

spotify_pid=$!
sleep 8

echo "Spotify PID: $spotify_pid"

if ! ps -p "$spotify_pid" >/dev/null 2>&1; then
  echo "Copied Spotify exited early. Stdout/stderr log:"
  tail -n 80 "$stdout_log" || true
  exit 1
fi

echo
echo "Probe load check:"
if [[ -f "$probe_log" ]] && rg -q 'native audio probe loaded' "$probe_log"; then
  rg -n 'native audio probe loaded|AudioComponentInstanceNew|AudioUnitSetProperty|AudioOutputUnitStart|AudioObjectSetPropertyData' "$probe_log" || true
else
  echo "Probe still did not load."
  echo "Stdout/stderr log: $stdout_log"
fi

echo
echo "If the probe loaded, play Spotify for 10-20 seconds and run:"
echo "  make inspect-probe-log"
echo
echo "Default PROBE_MODE=load only verifies injection stability."
echo "For narrower native probes, use make run-probe-unit or make run-probe-object."
echo "The component/all-audio probes are intentionally disabled in Makefile because AudioComponentInstanceNew recurses in Spotify."
echo
echo "AppleScript may still target the official Spotify app. Prefer clicking Play in the instrumented app window."
