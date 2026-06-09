#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${OUT_DIR:-build/native-audio-probe}"
PROBE_MODE="${PROBE_MODE:-load}"

defines=("-DSPOTIFY_NATIVE_AUDIO_PROBE_MODE=\"$PROBE_MODE\"")

case "$PROBE_MODE" in
  load)
    OUT_DYLIB="$OUT_DIR/libSpotifyNativeAudioProbeLoad.dylib"
    ;;
  component)
    OUT_DYLIB="$OUT_DIR/libSpotifyNativeAudioProbeComponent.dylib"
    defines+=("-DPROBE_AUDIO_COMPONENT")
    ;;
  unit)
    OUT_DYLIB="$OUT_DIR/libSpotifyNativeAudioProbeUnit.dylib"
    defines+=("-DPROBE_AUDIO_UNIT")
    ;;
  object)
    OUT_DYLIB="$OUT_DIR/libSpotifyNativeAudioProbeObject.dylib"
    defines+=("-DPROBE_AUDIO_OBJECT")
    ;;
  audio)
    OUT_DYLIB="$OUT_DIR/libSpotifyNativeAudioProbeAudio.dylib"
    defines+=("-DPROBE_AUDIO_COMPONENT" "-DPROBE_AUDIO_UNIT" "-DPROBE_AUDIO_OBJECT")
    ;;
  *)
    echo "Unknown PROBE_MODE=$PROBE_MODE. Use load, component, unit, object, or audio." >&2
    exit 64
    ;;
esac

mkdir -p "$OUT_DIR"

xcrun clang \
  -dynamiclib \
  -O2 \
  -Wall \
  -Wextra \
  -Wno-unused-parameter \
  -Wno-unused-function \
  "${defines[@]}" \
  tools/native_audio_probe.c \
  -o "$OUT_DYLIB" \
  -framework AudioToolbox \
  -framework AudioUnit \
  -framework CoreAudio

codesign --force --sign - "$OUT_DYLIB" >/dev/null

echo "$OUT_DYLIB"
