# Changelog

## Unreleased

### Added
- Glass can be moved and configured in Blizzard's Edit Mode: width, height, font, font sizes, background opacity and fade out delay (`EditMode.lua`, using LibEditMode).

### Fixed
- Messages appeared twice after creating a new chat tab, because the default chat frame became visible behind Glass (`UIManager.lua`).

## 1.9.0-forever1 (beta)

First release of the WoW: Forever fork, based on Glass 1.9.0-alpha1.

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
