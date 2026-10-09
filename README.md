# Glass Forever (beta)

A fork of [Glass](https://github.com/mixxorz/Glass) by Mitchel Cabuloy, adapted to work on **WoW: Forever**.

Glass is a clean, fading chat replacement. The original addon is no longer maintained, and recent changes to the WoW addon API broke it. This fork fixes those problems and adds a few quality-of-life features.

> **Status: beta.** Tested by one person, on WoW: Forever only. Please report bugs.

## What was fixed

- **"Secret number" errors.** The game now returns protected ("secret") values for text height and scroll position, which addons can't do arithmetic on. Glass now falls back to values it controls itself (`MessageLine.lua`, `SlidingMessageFrame.lua`).
- **Blank chat on login.** The chat panel is now shown automatically after the UI loads.
- **Tabs showing blank after switching.** The panel of the selected tab is always shown, and the others are hidden, so tabs no longer end up empty or overlapping.
- **Whisper tabs.** Closing and re-opening a whisper window no longer causes a "rehook" error or an empty tab.
- **Combat Log text cut off** at the left edge. It now has the same margin as the other tabs.

## New features

- **Colored tab glow.** When a message arrives for a tab that isn't selected, the tab glows in the color of that chat type (guild green, party blue, and so on). This works by default for any tab you create, based on the message types the tab shows. General and Combat Log are excluded.
- **Dock reveal.** The tab bar appears for a few seconds when such a message arrives, so you notice it even if the chat has faded out.
- **Selected tab indicator.** A thin line above the active tab.
- **Copy from chat.** Web links are clickable and open a window to copy them. Right-click a tab and choose "Copy chat text" to copy its messages.
- **Short channel names** (optional, in `/glass` → Messages). `[1]` instead of `[1. General]`, `[P]` instead of `[Party]`, and so on.
- **Chat history.** The last 50 messages of each tab are kept when you log out and shown again when you come back (per character, can be turned off in `/glass` → Messages).
- **Separate chat windows.** Drag a tab out of the dock to make it a separate chat window, drag it back to join Glass again.
- **Options in the game's Options window** (Options > AddOns > Glass Forever), with the game's own look. `/glass` opens them.
- **Edit Mode support.** Move Glass and change its size, fonts, opacity, animations and edit box position from Blizzard's Edit Mode.

## Known limitations

- The game no longer tells addons the exact height of a message. Glass counts the lines itself, but when the game also hides the message text (this can happen inside instances), a long message may still overlap the next one.
- Only tested on WoW: Forever. It may not work on other clients.

## Installation

1. Download the latest `.zip` from the Releases page.
2. Extract it into `Interface/AddOns/`.
3. Restart the game completely (a `/reload` may not pick up changed files).

## Credits and license

Original addon: **Glass** by Mitchel Cabuloy, MIT license.
Fork changes: Nelson Abrantes, 2026.

Released under the MIT license. See `LICENSE`. Bundled libraries (AceHook, LibEasing, lodash, etc.) keep their own licenses.
