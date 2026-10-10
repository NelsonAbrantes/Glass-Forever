# Changelog

Versions are named `X.Y.Z-forever`. The fork uses its own numbering: `0.x` while in beta, `1.0.0-forever` will be the first stable release.

## 0.11.0-forever (beta, unreleased)

### Added
- Tabs options (Options > AddOns > Glass Forever > Tabs): tab font and font size, tab bar height, spacing between tabs, tab bar background opacity, and an option to turn off the tab alerts (colored glow and tab bar reveal). Tab font size and tab bar height are also in Edit Mode (`OptionsPanel.lua`, `EditMode.lua`, `Fonts.lua`, `ChatDock.lua`, `ChatTab.lua`, `UIManager.lua`).
- Tab bar position: above or below the messages, with horizontal and vertical offsets for fine adjustment (`ChatDock.lua`, `SlidingMessageFrame.lua`, `ChatTab.lua`).
- Tab alignment: left, center or right along the tab bar (`ChatDock.lua`, `ChatTab.lua`).
- "Fade out" options for the tab bar (Tabs) and for the messages (Messages): turn them off to keep the tab bar or the messages always visible (`ChatDock.lua`, `SlidingMessageFrame.lua`, `UIManager.lua`).
- Tab bar position, alignment and both "Fade out" options are also in Edit Mode (`EditMode.lua`).

### Fixed
- The "jump to the newest messages" button didn't move when the chat height changed (`ScrollOverlayFrame.lua`).
- Long tab names were cut ("Combat L..."): the tab is now as wide as the full name (`ChatTab.lua`).
- The Combat Log covered the tabs when the tab bar was made taller. It now follows the tab bar height (`SlidingMessageFrame.lua`).
- Whisper tabs were cut off at the end of the tab bar, and with several whispers most of them couldn't be seen. When the tabs don't fit, they now get less space around their names first, then whisper names get "...", then the other chats' names. The game's arrow with the list of chats only appears when even that isn't enough (`ChatDock.lua`, `ChatTab.lua`).

## 0.10.1-forever (beta) (2026-10-10)

### Fixed
- Changing the font, font size, width or height (in the options or in Edit Mode) caused a "Usage: self:SetWidth(width)" error. The tabs now resize to their text again (`ChatTab.lua`).

## 0.10.0-forever (beta) (2026-10-10)

### Added
- Glass can be moved and configured in Blizzard's Edit Mode: width, height, font, font sizes, background opacity and fade out delay (`EditMode.lua`, using LibEditMode).
- Web links in chat (`https://...`, `www....`) are clickable and open a window to copy them (`TextProcessing.lua`, `Hyperlinks.lua`, `Copy.lua`).
- "Copy chat text" in the tab right-click menu shows the tab's messages as plain text, ready to copy (`Copy.lua`).
- "Short channel names" option: `[1]` instead of `[1. General]`, `[P]` instead of `[Party]`, `[G]` instead of `[Guild]`, and so on (`TextProcessing.lua`).
- Chat history: the last 50 messages of each tab are saved per character and shown again when you log back in. Can be turned off with "Keep chat history" (`History.lua`).
- More settings in Edit Mode: fade in, fade out and slide in durations, show on mouse over, short channel names, edit box position and edit box opacity (`EditMode.lua`).
- Glass options are in the game's Options window (Options > AddOns > Glass Forever), built with the game's own controls. `/glass` opens them (`OptionsPanel.lua`).
- Tabs (including whispers) can be dragged out of the dock to become separate chat windows, and dragged back to join Glass again, as in the default chat. Separate windows use the Glass font and keep their place after logging out (`UIManager.lua`, `SlidingMessageFrame.lua`, `ChatDock.lua`).

### Changed
- The Copy window, the "unlocked" dialog and the option buttons use the current game style (bronze border, red buttons) instead of the old Classic look (`Copy.lua`, `MoverDialog.lua`, `Button.lua`).
- The chat position (X/Y offset, anchor) is no longer in the options; move the chat in Edit Mode or with "Unlock frame".
- "Unlock frame" highlights the chat with the Edit Mode look (blue border) instead of a green box (`MoverFrame.lua`).
- The "What's new" window shows the Glass Forever versions, in the current game style (`News.lua`).
- Windows, messages and the Edit Mode entry say "Glass Forever" instead of "Glass".
- The "Glass has just been updated" message now appears whenever the version changes, not only when the number goes up (`UIManager.lua`).

### Fixed
- Messages appeared twice after creating a new chat tab, because the default chat frame became visible behind Glass (`UIManager.lua`).
- Long messages that wrap onto several lines no longer overlap the next message when the game hides their height. Glass now counts the lines itself (`MessageLine.lua`).
- "Attempt to perform string conversion on a secret string value (execution tainted by 'Glass')" errors. Glass replaced some of the game's chat functions, which tainted the game's code and broke it on protected ("secret") messages. It now uses secure hooks that run after the game's code (`SlidingMessageFrame.lua`, `ChatTab.lua`, `UIManager.lua`).
- The background of the "jump to the newest messages" button used a wrong image path (`ScrollOverlayFrame.lua`).
- With short channel names on, channel notices ("Changed Channel: ...") showed only the number. They now keep the full channel name (`TextProcessing.lua`).
- Frame rate spikes: moving the mouse over the chat animated the messages of every tab, including hidden ones; the update loop repeated itself after slow frames; the selected tab line was resized every frame; removing old messages created garbage; long messages measured the same words again and again. All fixed (`SlidingMessageFrame.lua`, `UIManager.lua`, `ChatTab.lua`, `MessageLine.lua`).
- Messages that arrived in a hidden tab now fade out normally when the tab is opened (`SlidingMessageFrame.lua`).
- Whispers didn't reveal the tab bar and their tab glow was invisible. Whisper tabs now glow steadily in the whisper color and the tab bar appears, like the other chat types (`UIManager.lua`, `ChatTab.lua`).

## 1.9.0-forever1 (beta)

First release of the WoW: Forever fork, based on Glass 1.9.0-alpha1. It was released with the original Glass version number; later releases use their own numbering, starting at 0.10.0-forever (see above).

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
