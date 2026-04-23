# Release Guide

## Build Artifacts

- `dist/MacLaunch.app`
- `dist/MacLaunch-<version>.app`
- `dist/MacLaunch.dmg`
- `dist/MacLaunch-<version>.dmg`

## Build Commands

```bash
./scripts/setup_github_repo.sh
./scripts/package_app.sh
./scripts/package_dmg.sh
./scripts/release.sh
./scripts/publish_github_release.sh
```

## Source Distribution

When distributing a binary release, include:

- the matching source code snapshot
- `LICENSE`
- `README.md`

If you publish a GitHub release, attach the `.dmg` and a source archive from the same commit.
This project is distributed under the GNU GPL v3.0 or later.

## Versioning

- Update the root `VERSION` file before cutting a release.
- Keep the version tag and packaging outputs in sync.

## GitHub Release

- Run `./scripts/setup_github_repo.sh` first to verify git and GitHub CLI setup.
- Set the `origin` remote to `git@github.com:woshixieming/macLaunch.git`.
- Install and authenticate GitHub CLI with `gh auth login`.
- Run `./scripts/publish_github_release.sh` to package, tag, push, and publish.

## Notes

- Keep the version number in sync with your release tag.
- Verify the app launches from a clean machine before announcing a release.
- If you change the UI or packaging flow, update `README.md` and this file together.
