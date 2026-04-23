# Contributing

Thanks for helping improve MacLaunch.

## Ground Rules

- Keep changes small and focused.
- Preserve the macOS launcher feel and the current visual style.
- Avoid introducing new dependencies unless they clearly help the project.
- Follow the GPLv3 license for all contributions.

## Workflow

1. Create a branch for your change.
2. Make the code change and keep the app building.
3. Update `README.md` if the user-facing behavior changes.
4. Add or update tests when practical.
5. Open a pull request with a short summary and screenshots if the UI changed.

## Coding Notes

- Prefer SwiftUI and modern AppKit only where needed.
- Keep drag, paging, and settings behavior consistent across the app.
- Reuse existing patterns instead of introducing one-off abstractions.

## Reporting Issues

When filing an issue, include:

- macOS version
- Xcode version
- steps to reproduce
- expected behavior
- actual behavior

