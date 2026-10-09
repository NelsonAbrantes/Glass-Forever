# Changelog

Versions are named `X.Y.Z-forever`. The fork uses its own numbering: `0.x` while in beta, `1.0.0-forever` will be the first stable release.

## 0.9.1-forever (beta, unreleased)

### Added
- Glass can be moved and configured in Blizzard's Edit Mode: width, height, font, font sizes, background opacity and fade out delay (`EditMode.lua`, using LibEditMode).
- Web links in chat (`https://...`, `www....`) are clickable and open a window to copy them (`TextProcessing.lua`, `Hyperlinks.lua`, `Copy.lua`).
- "Copy chat text" in the tab right-click menu shows the tab's messages as plain text, ready to copy (`Copy.lua`).
- "Short channel names" option: `[1]` instead of `[1. General]`, `[P]` instead of `[Party]`, `[G]` instead of `[Guild]`, and so on (`TextProcessing.lua`).

### Changed
- The "Glass has just been updated" message now appears whenever the version changes, not only when the number goes up (`UIManager.lua`).

### Fixed
- Messages appeared twice after creating a new chat tab, because the default chat frame became visible behind Glass (`UIManager.lua`).
- Long messages that wrap onto several lines no longer overlap the next message when the game hides their height. Glass now counts the lines itself (`MessageLine.lua`).

## 1.9.0-forever1 (beta)

First release of the WoW: Forever fork, based on Glass 1.9.0-alpha1. It was released with the original Glass version number; later releases restart at 0.9.x (see above).

### Fixed
- Arithmetic on "secret number" values when sizing message lines (`MessageLine.lua`).
- Arithmetic on "secret number" values when scrolling with the mouse wheel (`SlidingMessageFrame.lua`).
- Chat was blank after login until switching tabs (`UIManager.lua`).
- Tabs showing blank or overlapping after switching (`UIManager.lua`).
- Whisper windows: error when closing, and blank tab when re-opening (`UIManager.lua`, `SlidingMessageFrame.lua`).
- Combat Log text was cut off on the left edge (`SlidingMessageFrame.lua`).

### Added
- Tab glow in the color of the chat type, for any tab (`UIManager.lua`, `ChatTab.lua`).
- Tab bar is revealed when a message arrives for an unselected tab (`UIManager.lua`).
- Thin line above the selected tab (`ChatTab.lua`).

### Known issues
- Multi-line messages may overlap.
- Only tested on WoW: Forever.
