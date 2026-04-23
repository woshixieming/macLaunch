#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/dmg-staging"
APP_NAME="MacLaunch"
APP_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
APP_BUNDLE="$DIST_DIR/$APP_NAME-$APP_VERSION.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$APP_VERSION.dmg"
LATEST_DMG="$DIST_DIR/$APP_NAME.dmg"

"$ROOT_DIR/scripts/package_app.sh"

printf 'Packaging disk image under GPLv3. See %s/LICENSE for details.\n' "$ROOT_DIR"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
rm -f "$LATEST_DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

cp "$DMG_PATH" "$LATEST_DMG"

rm -rf "$STAGING_DIR"

printf 'Created dmg: %s\n' "$DMG_PATH"
printf 'Created latest dmg: %s\n' "$LATEST_DMG"
