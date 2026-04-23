#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="MacLaunch"
APP_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
TAG="v$APP_VERSION"
REPO="${GH_REPOSITORY:-woshixieming/macLaunch}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo)
            [[ $# -ge 2 ]] || { printf 'Missing value for --repo\n' >&2; exit 1; }
            REPO="$2"
            shift 2
            ;;
        --help|-h)
            cat <<'EOF'
Usage: scripts/publish_github_release.sh [--repo owner/name]

Builds the app and dmg, tags the release, pushes the tag, and creates a GitHub Release.
EOF
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

command -v git >/dev/null 2>&1 || {
    printf 'git is required for GitHub publishing.\n' >&2
    exit 1
}

command -v gh >/dev/null 2>&1 || {
    printf 'gh is required for GitHub publishing. Install GitHub CLI and run gh auth login first.\n' >&2
    exit 1
}

git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    printf 'This script must be run from inside a git repository.\n' >&2
    exit 1
}

REMOTE_URL="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"
if [[ -n "$REMOTE_URL" ]]; then
    printf 'Origin remote: %s\n' "$REMOTE_URL"
fi

printf 'Building release artifacts for %s\n' "$TAG"
"$ROOT_DIR/scripts/release.sh"

if git -C "$ROOT_DIR" rev-parse --verify "$TAG" >/dev/null 2>&1; then
    printf 'Tag %s already exists locally.\n' "$TAG"
else
    git -C "$ROOT_DIR" tag -a "$TAG" -m "MacLaunch $APP_VERSION"
    printf 'Created tag %s\n' "$TAG"
fi

git -C "$ROOT_DIR" push origin HEAD
git -C "$ROOT_DIR" push origin "$TAG"

gh release create "$TAG" \
    --repo "$REPO" \
    --title "MacLaunch $APP_VERSION" \
    --notes-file "$ROOT_DIR/RELEASE.md" \
    "$DIST_DIR/$APP_NAME-$APP_VERSION.dmg"

printf 'GitHub release %s published to %s\n' "$TAG" "$REPO"
