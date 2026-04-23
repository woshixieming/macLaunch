#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"

printf 'Starting release %s\n' "$APP_VERSION"

"$ROOT_DIR/scripts/package_app.sh"
"$ROOT_DIR/scripts/package_dmg.sh"

printf 'Release %s complete.\n' "$APP_VERSION"
printf 'Artifacts:\n'
printf '  %s\n' "$ROOT_DIR/dist/MacLaunch.app"
printf '  %s\n' "$ROOT_DIR/dist/MacLaunch-%s.app" "$APP_VERSION"
printf '  %s\n' "$ROOT_DIR/dist/MacLaunch.dmg"
printf '  %s\n' "$ROOT_DIR/dist/MacLaunch-%s.dmg" "$APP_VERSION"
