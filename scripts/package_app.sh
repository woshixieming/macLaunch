#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/.derived"
BUILD_DIR="$DERIVED_DATA_DIR/Build/Products/Release"
APP_NAME="MacLaunch"
APP_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
DIST_APP="$DIST_DIR/$APP_NAME.app"
VERSIONED_APP="$DIST_DIR/$APP_NAME-$APP_VERSION.app"

mkdir -p "$DIST_DIR"

printf 'Building under GPLv3. See %s/LICENSE for details.\n' "$ROOT_DIR"

xcodebuild \
  -project "$ROOT_DIR/MacLaunch.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  MARKETING_VERSION="$APP_VERSION" \
  CURRENT_PROJECT_VERSION="$APP_VERSION" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  build

rm -rf "$DIST_APP"
rm -rf "$VERSIONED_APP"
ditto "$APP_BUNDLE" "$DIST_APP"
ditto "$APP_BUNDLE" "$VERSIONED_APP"

printf 'Created app bundle: %s\n' "$DIST_APP"
printf 'Created versioned app bundle: %s\n' "$VERSIONED_APP"
