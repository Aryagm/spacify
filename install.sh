#!/bin/sh
# Installs Spacify: downloads the latest release, moves it to /Applications,
# and approves it locally. The app is open source and unsigned, so this
# clears the Gatekeeper quarantine flag and applies a local ad-hoc signature
# instead of requiring a notarized download.
set -eu

REPO="Aryagm/spacify"
APP="/Applications/Spacify.app"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading the latest Spacify release..."
curl -fsSL "https://github.com/$REPO/releases/latest/download/Spacify.zip" -o "$TMP/Spacify.zip"

echo "Installing to /Applications..."
pkill -x Spacify 2>/dev/null || true
rm -rf "$APP"
ditto -x -k "$TMP/Spacify.zip" /Applications

echo "Approving Spacify on this Mac..."
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP"

echo "Launching..."
open "$APP"
echo "Done. Look for the earbuds icon in your menu bar."
echo "macOS will ask for System Audio Recording permission the first time you spatialize an app."
