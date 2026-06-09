#!/usr/bin/env bash
set -euo pipefail

SPOTIFY_APP="${SPOTIFY_APP:-/Applications/Spotify.app}"
PROBE_APP="${PROBE_APP:-build/SpotifyNativeProbe.app}"
ENTITLEMENTS="${ENTITLEMENTS:-tools/spotify_probe_entitlements.plist}"
PROBE_BUNDLE_ID="${PROBE_BUNDLE_ID:-com.spotify.client.probe}"
PROBE_BUNDLE_NAME="${PROBE_BUNDLE_NAME:-Spotify Probe}"

if [[ ! -d "$SPOTIFY_APP" ]]; then
  echo "Spotify app not found: $SPOTIFY_APP" >&2
  exit 1
fi

if [[ ! -f "$ENTITLEMENTS" ]]; then
  echo "Entitlements file not found: $ENTITLEMENTS" >&2
  exit 1
fi

if [[ "${REFRESH_SPOTIFY_COPY:-0}" == "1" || ! -d "$PROBE_APP" ]]; then
  echo "Copying Spotify to $PROBE_APP..." >&2
  rm -rf "$PROBE_APP"
  mkdir -p "$(dirname "$PROBE_APP")"
  ditto "$SPOTIFY_APP" "$PROBE_APP"
fi

xattr -dr com.apple.quarantine "$PROBE_APP" 2>/dev/null || true

echo "Setting probe bundle identity to $PROBE_BUNDLE_ID..." >&2
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $PROBE_BUNDLE_ID" "$PROBE_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $PROBE_BUNDLE_NAME" "$PROBE_APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleName string $PROBE_BUNDLE_NAME" "$PROBE_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $PROBE_BUNDLE_NAME" "$PROBE_APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $PROBE_BUNDLE_NAME" "$PROBE_APP/Contents/Info.plist"

echo "Ad-hoc signing copied Spotify for local instrumentation..." >&2
codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$PROBE_APP" >/dev/null

echo "$PROBE_APP"
