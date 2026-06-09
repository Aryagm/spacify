#!/usr/bin/env bash
set -euo pipefail

latest_log="$(ls -t logs/spotify-probe-copy-native-audio-*.log 2>/dev/null | head -n 1 || true)"

if [[ -z "$latest_log" ]]; then
  echo "No native probe logs found. Run make run-probe-copy first." >&2
  exit 1
fi

echo "Log: $latest_log"
echo

interesting_pattern='native audio probe loaded|AudioComponentInstanceNew|AudioUnitSetProperty|  ASBD|  RenderCallback|  ChannelLayout|  ChannelDescription|  CurrentDevice|  EnableIO|AudioUnitInitialize|AudioOutputUnitStart|AudioOutputUnitStop|AudioUnitUninitialize|AudioComponentInstanceDispose|AudioObjectSetPropertyData'

count_matches() {
  local pattern="$1"
  local count
  count="$(rg -c "$pattern" "$latest_log" 2>/dev/null || true)"
  if [[ -z "$count" ]]; then
    echo 0
  else
    echo "$count"
  fi
}

load_count="$(count_matches 'native audio probe loaded')"
component_begin_count="$(count_matches 'AudioComponentInstanceNew begin')"
component_result_count="$(count_matches 'AudioComponentInstanceNew type=.*result')"
unit_set_count="$(count_matches 'AudioUnitSetProperty begin')"
unit_set_result_count="$(count_matches 'AudioUnitSetProperty property=.*result=')"
unit_initialize_count="$(count_matches 'AudioUnitInitialize begin')"
unit_initialize_result_count="$(count_matches 'AudioUnitInitialize unit=.*result=')"
unit_start_count="$(count_matches 'AudioOutputUnitStart begin')"
unit_start_result_count="$(count_matches 'AudioOutputUnitStart unit=.*result=')"
object_set_count="$(count_matches 'AudioObjectSetPropertyData begin')"
missing_original_count="$(count_matches 'missing original|original lookup .* failed')"

echo "Counts:"
printf '  load events: %s\n' "$load_count"
printf '  component creates started: %s\n' "$component_begin_count"
printf '  component creates returned: %s\n' "$component_result_count"
printf '  AudioUnitSetProperty calls: %s\n' "$unit_set_count"
printf '  AudioUnitSetProperty returns: %s\n' "$unit_set_result_count"
printf '  AudioUnitInitialize calls: %s\n' "$unit_initialize_count"
printf '  AudioUnitInitialize returns: %s\n' "$unit_initialize_result_count"
printf '  AudioOutputUnitStart calls: %s\n' "$unit_start_count"
printf '  AudioOutputUnitStart returns: %s\n' "$unit_start_result_count"
printf '  AudioObjectSetPropertyData calls: %s\n' "$object_set_count"
printf '  missing original lookups: %s\n' "$missing_original_count"
echo

if (( component_begin_count > 100 && component_result_count == 0 )); then
  echo "The component probe is recursing before AudioComponentInstanceNew returns."
  echo "That matches Spotify closing when playback starts. Use make run-probe-unit next."
  echo
fi

if (( unit_set_count > 100 && unit_set_result_count == 0 )); then
  echo "The unit probe is recursing before AudioUnitSetProperty returns."
  echo "Rebuild from the latest source and rerun make run-probe-unit."
  echo
fi

if (( missing_original_count > 0 )); then
  echo "At least one hook could not resolve the original system function."
  echo "That means the interpose path is not usable for that function yet."
  echo
fi

matches_file="$(mktemp)"
trap 'rm -f "$matches_file"' EXIT
rg -n "$interesting_pattern" "$latest_log" >"$matches_file" || true

if [[ -s "$matches_file" ]]; then
  total_matches="$(wc -l <"$matches_file" | tr -d ' ')"
  echo "First matching events:"
  head -n 40 "$matches_file"
  if (( total_matches > 60 )); then
    echo
    echo "... skipped $((total_matches - 60)) matching events ..."
    echo
    echo "Last matching events:"
    tail -n 20 "$matches_file"
  elif (( total_matches > 40 )); then
    echo
    echo "Remaining matching events:"
    tail -n $((total_matches - 40)) "$matches_file"
  fi
else
  echo "No native probe events matched."
fi

echo

if rg -q 'mode=load' "$latest_log" && ! rg -q 'Audio(ComponentInstance|Unit|Object)' "$latest_log"; then
  echo "This is a load-only probe log. That only verifies injection stability; it will not show CoreAudio calls."
  echo
  echo "Next probes:"
  echo "  make run-probe-unit"
  echo "  make run-probe-object"
elif rg -q 'mode=unit' "$latest_log" &&
     (( unit_set_count == 0 && unit_initialize_count == 0 && unit_start_count == 0 )); then
  echo "The unit probe loaded, but no AudioUnit calls are captured yet."
  echo "Click Play in the instrumented Spotify window, let it run for 10-20 seconds, then rerun make inspect-probe-log."
elif rg -q 'mode=object' "$latest_log" && (( object_set_count == 0 )); then
  echo "The object probe loaded, but no AudioObjectSetPropertyData calls are captured yet."
  echo "Click Play in the instrumented Spotify window, let it run for 10-20 seconds, then rerun make inspect-probe-log."
fi
