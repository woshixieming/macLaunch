# MacLaunch 1.0.4

## Highlights

- Fixed the remaining application folder watcher crash in version 1.0.3.
- Moved app folder change callbacks onto the main queue to match the app catalog's MainActor isolation.

## Notes

- This release is distributed under the GNU GPL v3.0 or later.
- If an older MacLaunch process is still running, quit it before opening the new build.
