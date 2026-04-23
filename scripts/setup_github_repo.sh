#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEFAULT_REMOTE="git@github.com:woshixieming/macLaunch.git"
REMOTE_URL="${1:-$DEFAULT_REMOTE}"

if ! command -v git >/dev/null 2>&1; then
    printf 'git is required.\n' >&2
    exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
    printf 'GitHub CLI is not installed. Install gh and run gh auth login before publishing.\n' >&2
else
    if gh auth status >/dev/null 2>&1; then
        printf 'gh authentication looks good.\n'
    else
        printf 'gh is installed but not authenticated. Run gh auth login.\n'
    fi
fi

if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'Git repository detected at %s\n' "$ROOT_DIR"
else
    printf 'No git repository found at %s\n' "$ROOT_DIR"
    printf 'You can initialize one with:\n'
    printf '  cd %s && git init\n' "$ROOT_DIR"
    printf 'Then add and commit your files before publishing.\n'
    exit 0
fi

CURRENT_REMOTE="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"
if [[ -z "$CURRENT_REMOTE" ]]; then
    git -C "$ROOT_DIR" remote add origin "$REMOTE_URL"
    printf 'Added origin remote: %s\n' "$REMOTE_URL"
elif [[ "$CURRENT_REMOTE" != "$REMOTE_URL" ]]; then
    printf 'origin already exists: %s\n' "$CURRENT_REMOTE"
    printf 'Expected remote: %s\n' "$REMOTE_URL"
    printf 'Update it manually if needed.\n'
else
    printf 'origin remote already matches: %s\n' "$CURRENT_REMOTE"
fi

printf 'Repository setup check complete.\n'
