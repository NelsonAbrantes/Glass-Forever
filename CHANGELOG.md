# Changelog

Versions are named `X.Y.Z-forever`. The fork uses its own numbering: `0.x` were the beta versions, `1.0.0-forever` is the first stable release.

## 1.0.0-forever (2026-10-19)

### Added
- Guild and Party tabs: the first time you log in with a character, Glass offers to create them. Guild, officer and party, raid and instance messages then move out of General into their own tabs, and the interface reloads. Asked once per character, and not if the tabs already exist (`DefaultTabs.lua`, `Button.lua`).
- Track a recipe from the chat: right click a recipe someone linked from their profession window (e.g. "[Alchemy: Greater Healing Potion]") and choose "Track Recipe" (or "Untrack Recipe") (`Hyperlinks.lua`).
- Emotes: :) :( :D ;) :P :O :| :/ xD <3 </3 D: :S :* B) :'( >:( ^^ -_- o.O :3 T_T and :$ in a message show as small faces (a little taller than the text), in the chat and in separate windows. Options > Messages > Emotes: Glass (gold outlines, the default), Classic (yellow faces) or Off. Only players with Glass see them (`TextProcessing.lua`, `OptionsPanel.lua`, `UIManager.lua`, `Assets/Emotes`).
- Emote button (Messages > Emote button, off by default): a small face at the right of the chat box opens the list of emotes; a click writes one where you type (`EditBox.lua`).
- Unread count (Tabs > Unread count, on by default): a small number by the name of a tab you're not looking at, with how many messages came in since (`ChatTab.lua`, `SlidingMessageFrame.lua`).
- Search messages: in a tab's right-click menu, a window to search that tab's messages as you type (`Copy.lua`).
- Timestamps (Messages > Timestamps: off by default, 17:49 or 17:49:05): the time in front of each message, kept with the history. Shift+click the time to write the message in the chat box, click it to copy it (`TextProcessing.lua`, `SlidingMessageFrame.lua`, `History.lua`, `Hyperlinks.lua`).
- Class icons and race icons in front of players' names, and first names only ("Aehya" for "Aehya Bfc"), each one an option in Messages, off by default. Skyborne get an icon too (`TextProcessing.lua`).
- Export and import profiles as text (Profiles page), to keep or share your settings (`OptionsPanel.lua`).

### Changed
- "Create profile" asks for the new profile's name (`OptionsPanel.lua`).
- The chat buttons beside the chat sit a little closer to it (`ChatButtons.lua`).
- Whispers open in their own tab: the first time Glass runs on an account, the game option New Whispers (Options > Social) goes from In-line to New Tab, once, with a line in the chat saying how to change it back (`DefaultTabs.lua`).
- Players from your Recent Allies list get a Glass icon after their name in the chat (one person, in the Glass gold) instead of the game's yellow one, also in front of their name on a whisper tab (`TextProcessing.lua`, `ChatTab.lua`, `Assets/allyIcon.tga`).
- Separate windows look like the main chat: the same font, shadow and line spacing, the full chat background opacity (they looked lighter), and a window opened with "Open in Separate Window" gets the chat's font size (`SlidingMessageFrame.lua`, `Fonts.lua`, `Hyperlinks.lua`).

### Fixed
- In a busy chat, everything vanished at once a while after the mouse left, even messages that had just arrived. Now only the messages shown when the mouse left go then; later ones fade out on their own time (`SlidingMessageFrame.lua`).
- Links in a separate window often needed several clicks to open: Glass redrew the window every second while the mouse was over it, which lost the click. It now redraws only just before the messages would fade, and never while a mouse button is held (`UIManager.lua`).
- The game's own orange tab glow could show under the Glass alert when many messages came in a row. Its art is removed; the Glass alert is the only one (`ChatTab.lua`).

## 0.15.1-forever (beta) (2026-10-14)

### Added
- "Open in Separate Window" in a channel's menu (right click "[2]" in the chat): the channel moves to a new window, already out of the chat, unlocked so it can be moved. Where it opens is in Options > General > Separate windows ("Opens at": above the chat by default, right or left of it, or the middle of the screen) (`Hyperlinks.lua`, `OptionsPanel.lua`).

### Changed
- The new message alert's gleam is part of the line's length, so it runs all along it even on short tabs; its light is no wider than the line, it fades out towards the ends like the line, and it shows as much on bright colors (Guild's green) as on darker ones (`ChatTab.lua`).
- Separate windows with the Glass look bring their faded messages back while the mouse is over them, like the Glass chat (`UIManager.lua`).
- Separate windows' scroll bar in the Glass look: a thin faint line with a slim marker in the Glass color, and arrows and a "scroll to bottom" button like the chat buttons. The marker no longer jumps for a moment when a message arrives (`SlidingMessageFrame.lua`, `Assets/Buttons`).
- Tabs only light up for guild, officer, party, raid and instance messages (and whispers): say, yell and emotes from anyone nearby lit them all the time (`UIManager.lua`, `OptionsPanel.lua`).

### Fixed
- "Move to New Window" in a channel's menu gave an error and left a broken window (named "Chat 6", not filtered, not updating): clicking a link in Glass didn't tell the game which chat window it was in. Links now pass their window, and that menu option gets it; it is now called "Move to New Tab", since it opens a tab in the chat (#1) (`MessageLine.lua`, `SlidingMessageFrame.lua`, `Hyperlinks.lua`).
- "Copy Character Name" in a player's menu opened from the chat gave an error: the game only lets its own menus copy to the clipboard. It now opens the Glass copy window with the name selected (`Hyperlinks.lua`).
- Text in a window opened with "Move to New Window" was centered (`Fonts.lua`, `SlidingMessageFrame.lua`).
- The new message line crossed the tab name: the game now and then puts the name back a little lower, and a separate window's tab has another height. The name goes back to its place each time, and the line is placed from the name itself (`ChatTab.lua`).

## 0.15.0-forever (beta) (2026-10-14)

### Added
- Tab animations for every style ("Selected tab animation", Options > Tabs). Framed, Solid, Pill and Glossy: with Slide the selected look travels from the old tab to the new one, stretching to its size; with Grow it opens from the middle of the new tab with a small pop while it shrinks away on the old one. Their hover look comes and goes softly too. Underline's bar slides or grows like Minimal's line (`ChatTab.lua`, `OptionsPanel.lua`).
- "Class color" accent for the selected tab: the color of your character's class, in every style (`ChatTab.lua`, `OptionsPanel.lua`).

- New message alert drawn by Glass: a line under the tab name in the chat type color, with a glow that breathes softly and a gleam of light running along it while the tab is unread. It goes away as soon as the tab is read (`ChatTab.lua`, `UIManager.lua`).

### Changed
- Underline's selected bar has softened ends and a glow rising from it that lights the tab name from below (`ChatTab.lua`).
- Images sorted into `Assets/Buttons` and `Assets/Tabs`.
- Less memory churn from the tab animations and alerts: functions, lists and colors are made once and reused (`ChatTab.lua`).

- Lighter when the mouse leaves the chat or a tab is shown: one timer fades all the messages instead of one per message (up to 128 each time); tab width and name color corrections reuse the same functions (`SlidingMessageFrame.lua`, `ChatTab.lua`).

### Fixed
- Tab names didn't get solid with the mouse over the chat (the game's own chat window, hidden under Glass, never feels the mouse). They're now fully solid while the mouse is over the chat or the tab bar, and fade with the messages afterwards (`ChatTab.lua`).
- The tab bar now comes back when the mouse is already over the chat while it fades out (`MainContainerFrame.lua`).
- Memory jumps of tens of MB: after the chat changed size, the game asks to lay out the tabs every frame (sometimes for good), and Glass measured all the tabs again each time. It now does that only when the tabs really changed (`ChatDock.lua`).
- Tab names flickered when the mouse came over the chat: while the tab bar fades back in, the game keeps the tabs' old opacity, and Glass kept making them solid. The tabs now wait solid while the bar is hidden, and the game's own fade no longer mixes with Glass's when the mouse leaves (`ChatTab.lua`).

## 0.14.1-forever (beta) (2026-10-13)

### Fixed
- A new whisper (or any second chat window) gave an error and its tab kept the game's look, with its name cut short. Since 0.13.0, each chat window hooked the edit box with AceHook's HookScript instead of the frame's own (`ScrollOverlayFrame.lua`).

## 0.14.0-forever (beta) (2026-10-12)

### Added
- "Selected line animation" option (Options > Tabs): Slide (the line slides from the old tab to the new one, the default), Grow (it opens from the middle of the new tab) or Off (`ChatTab.lua`, `OptionsPanel.lua`).
- A thin dark outline around the chat button icons and the separate window buttons, so they stand out on any background (`ChatButtons.lua`, new `*Outline.tga` images).

### Changed
- The selected tab line (Minimal style) fades out towards its ends and has a soft glow into the tab. It's now one line for the whole tab bar, so it's never cut off (`ChatTab.lua`, new `tabGlow.tga`).
- Less memory churn in busy chats: no new timer function per message, no copies of message text without codes, no copied message queues (`FadingFrame.lua`, `utils.lua`, `SlidingMessageFrame.lua`).
- Lighter every frame: the selected tab and its line are checked about 30 times a second instead of every frame (every frame only while the line slides), and tab styles are compared without building text (`UIManager.lua`, `ChatTab.lua`).
- The "Previous session" line between old and new messages is now centered, in a dim gold, with a thin line on each side that fades out ("Previous session · 12 Oct, 14:30"), instead of a row of dashes. Lines saved by earlier versions get the new look too (`MessageLine.lua`, `History.lua`, `SlidingMessageFrame.lua`).

### Fixed
- The selected tab line sat 1px lower on Guild, Party and whisper tabs than on General and Combat Log: it now sits on the edge of the tab bar itself (`ChatTab.lua`).
- Changing the chat's height could freeze the game for a moment: every saved message of every tab was measured again at each step of the slider. Height and tab bar changes no longer do that (`SlidingMessageFrame.lua`, `ChatTab.lua`).
- Tabs aligned right (or centered) shook left and right: a tab a pixel wider or narrower moved them by a pixel, which changed the width again. They now only move when off by more than 2px, and the 1px gap the game leaves between tabs is counted (`ChatDock.lua`).

## 0.13.0-forever (beta) (2026-10-12)

### Added
- Spam filter (Options > Messages > Spam filter): hides messages that contain blocked words or phrases. Comes on, with a few gold seller phrases; "Edit list" opens a window to change them. Only Glass stops showing them (`SpamFilter.lua`, `SlidingMessageFrame.lua`, `OptionsPanel.lua`).
- Separate windows with the Glass look (Options > General > Separate windows): tabs dragged out of the chat become windows without the default border, with the Glass fading background while the mouse is over them, messages that fade out like in Glass, and minimize, maximize and resize buttons like the chat buttons. The minimized bar gets the Glass look too. Separate windows now come back where you left them after a reload, minimized if they were (`SlidingMessageFrame.lua`, `UIManager.lua`, `ChatButtons.lua`).
- Update notice: Glass Forever quietly tells other players in your guild and group which version it has; if someone has a newer one, a message in chat says so (once per session). Addons can't look online, so this is how the news spreads (`VersionCheck.lua`).
- "Tab style" option with seven styles: Minimal (as before), Framed (rounded background and bronze border), Solid (filled tabs), Underline (a bar under the selected tab), Pill (capsule-shaped tabs), Glossy (raised, glossy buttons) and Classic (the game's own tabs) (`ChatTab.lua`, new images in `Assets/`).
- "Accent color" option for the selected tab: style default, bronze, gold, cyan, silver, green, purple or red. Works on every style, Classic included (`ChatTab.lua`).
- "Name color" option for the tab names: auto, gold, white, silver or dark. Auto now uses white on the selected Solid tab when the letters have an outline, so it stays readable (`ChatTab.lua`, `OptionsPanel.lua`).
- "Arrow keys history" option (Options > Messages > Misc, on by default): the Up and Down arrows in the chat box go through what you typed, without holding Alt. The last 32 lines are kept after logging out or /reload, per character (`EditBox.lua`).

### Fixed
- After a reload, a separate window could end up hidden inside the chat, or be closed (`UIManager.lua`).
- Docking a window again showed the messages of the tab that was open before (`UIManager.lua`).
- The new message glow of a party tab looked white: pale chat colors are now stronger in the glow, and blues lean to sky blue (`ChatTab.lua`).
- "Unread messages" sat on top of the last messages and was hard to read: it's now under the chat (under the edit box while it's open) (`ScrollOverlayFrame.lua`, `NewMessageAlertFrame.lua`).
- Chinese and Korean letters showed as squares (and Cyrillic ones with some fonts): the chat, edit box, tabs and separate windows now use the game's own fonts for those letters, and the chosen font for the rest (`Fonts.lua`, `SlidingMessageFrame.lua`).

## 0.12.0-forever (beta) (2026-10-11)

### Added
- Edit box styles (Options > Edit Box > Style, also in Edit Mode): Minimal, the new default, fades out at the ends like the messages, with a thin line in the color of the chat you're typing in (say, party, whisper...); Solid is the previous plain dark box; Framed has rounded corners and a border in the chat's color (`EditBox.lua`, `OptionsPanel.lua`, `EditMode.lua`).
- Glass Forever shows its logo in the game's AddOns list (`Glass.toc`, `logo.tga`).

### Fixed
- The game's own edit box border could show again behind the Glass edit box (`EditBox.lua`).
- Tabs with no new messages piled up a "Previous session" line every session. Those lines now only show between messages, and history saved by earlier versions is tidied up (`History.lua`).
- The chat buttons could end up in the wrong place (where the game puts them) after a while. They now always go back to the chosen position (`ChatButtons.lua`).

## 0.11.0-forever (beta) (2026-10-11)

### Added
- Tabs options (Options > AddOns > Glass Forever > Tabs): tab font and font size, tab bar height, spacing between tabs, tab bar background opacity, and an option to turn off the tab alerts (colored glow and tab bar reveal). Tab font size and tab bar height are also in Edit Mode (`OptionsPanel.lua`, `EditMode.lua`, `Fonts.lua`, `ChatDock.lua`, `ChatTab.lua`, `UIManager.lua`).
- Tab bar position: above or below the messages, with horizontal and vertical offsets for fine adjustment (`ChatDock.lua`, `SlidingMessageFrame.lua`, `ChatTab.lua`).
- Tab alignment: left, center or right along the tab bar (`ChatDock.lua`, `ChatTab.lua`).
- "Fade out" options for the tab bar (Tabs) and for the messages (Messages): turn them off to keep the tab bar or the messages always visible (`ChatDock.lua`, `SlidingMessageFrame.lua`, `UIManager.lua`).
- Tab bar position, alignment and both "Fade out" options are also in Edit Mode (`EditMode.lua`).
- Chat buttons (Options > General > Chat buttons): the game's chat buttons (friends, channels and voice chat, mute and deafen, emotes and languages) can be shown beside, above or below the chat (left, right, top left, top right, bottom left or bottom right), with plain icons in the Glass color. They appear and fade with the tab bar. Off by default (`ChatButtons.lua`, `MainContainerFrame.lua`, `UIManager.lua`, `OptionsPanel.lua`).

### Fixed
- The "jump to the newest messages" button didn't move when the chat height changed (`ScrollOverlayFrame.lua`).
- Long tab names were cut ("Combat L..."): the tab is now as wide as the full name (`ChatTab.lua`).
- The Combat Log covered the tabs when the tab bar was made taller. It now follows the tab bar height (`SlidingMessageFrame.lua`).
- Whisper tabs were cut off at the end of the tab bar, and with several whispers most of them couldn't be seen. When the tabs don't fit, they now get less space around their names first, then whisper names get "...", then the other chats' names. The game's arrow with the list of chats only appears when even that isn't enough (`ChatDock.lua`, `ChatTab.lua`).
- Chat history from earlier sessions was shown mixed with the current one, with nothing to tell them apart. A gray line now marks where each earlier session ended, with its date and time (`History.lua`).

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
