#!/usr/bin/env bash
set -e

echo "👻 Installing GhostMouse for macOS..."
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

curl -fsSL "https://github.com/joeystdio/GhostMouse/releases/latest/download/GhostMouse.zip" -o "$TMP_DIR/GhostMouse.zip"
unzip -q "$TMP_DIR/GhostMouse.zip" -d "$TMP_DIR"

rm -rf "/Applications/GhostMouse.app"
mv "$TMP_DIR/GhostMouse.app" "/Applications/GhostMouse.app"
xattr -cr "/Applications/GhostMouse.app" 2>/dev/null || true

echo "✅ GhostMouse installed to /Applications/GhostMouse.app — launching now!"
open "/Applications/GhostMouse.app"
