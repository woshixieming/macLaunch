# Changelog

## 1.0.5

- Fixed launcher background clicks in app tile whitespace, app spacing, and the gap above pagination controls so those areas hide the launcher instead of doing nothing.
- Kept app launching limited to the app icon and app name.

## 1.0.4

- Fixed the remaining app folder watcher crash by delivering file system events on the main queue before scheduling catalog reloads.

## 1.0.3

- Fixed an occasional crash caused by application folder watchers calling MainActor-isolated code from a background queue.
- Limited app tile launch clicks to the app icon and app name, so surrounding empty space still hides the launcher.

## 1.0.2

- Added live app catalog refresh when Applications folders change.
- Added a setting to show or hide the recent apps section.
- Kept launched apps visible in the library while also recording them in recent apps.
- Added Simplified Chinese README.
- Fixed duplicate menu bar icons by using the SwiftUI menu bar extra only.
- Simplified the macOS app menu and made Settings more reliable from both the menu and `Command + ,`.

## 1.0.1

- Removed library tile backgrounds and corner badges for a cleaner app grid.
- Added system app prioritization so system applications appear at the end of the library.
- Improved page controls and simplified the library page layout.
