# MacLaunch

MacLaunch is a lightweight macOS launcher replacement built with SwiftUI.

## Features

- Global hotkey to show and hide the launcher
- Pinned apps with drag-to-reorder
- Recent apps section
- Library paging with customizable rows and columns
- Mouse wheel paging with separate sensitivity controls
- Keyboard navigation and quick launch shortcuts
- Click outside to dismiss

## Usage

- Press the configured hotkey to open the launcher.
- Click an app to launch it.
- Use `Esc` or click the background to close it.
- Drag apps to reorder pinned or library items.
- Open the Settings window from the menu bar to adjust layout and paging.

## Build & Package

Build a Release `.app` bundle:

```bash
./scripts/package_app.sh
```

Build a `.dmg` disk image:

```bash
./scripts/package_dmg.sh
```

Run the full release flow:

```bash
./scripts/release.sh
```

Publish a GitHub Release:

```bash
./scripts/setup_github_repo.sh
./scripts/publish_github_release.sh
```

The generated files are written to `dist/`.

## Repository Notes

- Build artifacts are ignored through `.gitignore`.
- Release outputs live in `dist/`.
- `VERSION` controls the release filename suffix.
- `scripts/setup_github_repo.sh` checks git and GitHub CLI setup.
- `scripts/publish_github_release.sh` pushes the tag and creates the GitHub Release.
- The project uses GPLv3 or later.
- See [`RELEASE.md`](./RELEASE.md) for packaging and distribution notes.

## License

This project is licensed under the GNU General Public License v3.0 or later.
See [`LICENSE`](./LICENSE) for the full text.
