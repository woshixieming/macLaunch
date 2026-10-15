# MacLaunch 1.0.9

## Highlights

- Fixed an app unexpectedly jumping to the end of the library when dropped in its existing position.
- Invalid or stale drag targets now leave the app order unchanged.
- Library and pinned app order is saved only when a drag actually changes the order.
- Added 42 regression cases covering adjacent positions, invalid IDs, cross-page ordering, pinned apps, and persistence.

## Notes

- This release is distributed under the GNU GPL v3.0 or later.
- System applications continue to appear after other applications.
- If an older MacLaunch process is still running, quit it before opening the new build.
