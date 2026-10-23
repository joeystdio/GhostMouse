#!/bin/zsh
set -e

cd "$(dirname "$0")"
ROOT_DIR="$(pwd)"

./build_app.sh

echo "4. Creating GhostMouse.dmg installer..."
STAGING_DIR="$ROOT_DIR/.dmg_staging"
DMG_PATH="$ROOT_DIR/GhostMouse.dmg"
ZIP_PATH="$ROOT_DIR/GhostMouse.zip"

rm -rf "$STAGING_DIR" "$DMG_PATH" "$ZIP_PATH"
mkdir -p "$STAGING_DIR"

cp -R "$ROOT_DIR/GhostMouse.app" "$STAGING_DIR/GhostMouse.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create -volname "GhostMouse" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

# Also create a notarization/release zip
ditto -c -k --keepParent "$ROOT_DIR/GhostMouse.app" "$ZIP_PATH"

# Optional Apple Notarization if KEYCHAIN_PROFILE is set (e.g. KEYCHAIN_PROFILE="notarytool-profile" ./release_dmg.sh)
if [ -n "$KEYCHAIN_PROFILE" ]; then
    echo "5. Submitting GhostMouse.dmg to Apple Notary Service..."
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
fi

echo "Done!"
ls -lh "$DMG_PATH" "$ZIP_PATH"
shasum -a 256 "$DMG_PATH" "$ZIP_PATH"
