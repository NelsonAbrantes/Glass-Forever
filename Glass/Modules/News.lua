local Core, Constants = unpack(select(2, ...))
local News = Core:GetModule("News")

-- luacheck: push ignore 113
local CreateFrame = CreateFrame
local UIParent = UIParent
-- luacheck: pop

local OPEN_NEWS = Constants.EVENTS.OPEN_NEWS

-- Version history shown in the "What's new" window. Newest first.
-- luacheck: push ignore 631
local CHANGELOG = {
  {
    name = "0.11.0-forever (beta)",
    items = {[[
What's new

- Tabs options (Options > AddOns > Glass Forever > Tabs): tab font and size, tab bar height, spacing between tabs, tab bar opacity, and an option to turn off the tab alerts.
- Tab bar position: above or below the messages, with fine adjustment left/right and up/down.
- Tab alignment: left, center or right.
- "Fade out" options: keep the tab bar or the messages always visible.
- Chat buttons (Options > General): show the game's chat buttons (friends, channels and voice chat, emotes and languages) next to the chat, with icons in the Glass style. Left, right, top left, top right, bottom left or bottom right.
- Tab bar position, alignment and the "Fade out" options are also in Edit Mode.

Bug fixes

- Long tab names are no longer cut ("Combat L...").
- Whisper tabs no longer get cut off at the end of the tab bar. When the tabs don't fit, names get shorter instead, whispers first.
- Chat history from earlier sessions is now separated from the current one by a line with the date and time.
- The Combat Log no longer covers the tabs when the tab bar is taller.
- The "jump to the newest messages" button now follows the chat height.
    ]]}
  },
  {
    name = "0.10.1-forever (beta)",
    items = {[[
Bug fixes

- Fixed an error when changing the font, font size, width or height, in the options or in Edit Mode.
    ]]}
  },
  {
    name = "0.10.0-forever (beta)",
    items = {[[
What's new

- Edit Mode: move Glass and change its size, fonts, opacity, animations and edit box position from Blizzard's Edit Mode.
- Options are now in the game's Options window (Options > AddOns > Glass Forever), with the game's own look. /glass opens them.
- Web links in chat are clickable and open a window to copy them.
- Right-click a tab and choose "Copy chat text" to copy its messages.
- Short channel names (optional): [1] instead of [1. General], [P] instead of [Party], and so on.
- Chat history: the last 50 messages of each tab come back when you log in again (per character, can be turned off).
- Drag a tab (including whispers) out of the chat to make it a separate window, and drag it back to join Glass again.
- Glass windows and buttons use the current game style.

Bug fixes

- Messages no longer appear twice after creating a new tab.
- Long messages no longer overlap the next message.
- Whispers now light up their tab in the whisper color and show the tab bar.
- Fixed errors with protected ("secret") chat messages, for example in combat or instances.
- Better performance: fixed frame rate spikes, especially when moving the mouse over the chat and in busy chats.
- Channel notices ("Changed Channel: ...") show the full channel name with short channel names on.
    ]]}
  },
  {
    name = "1.9.0-forever1 (beta)",
    items = {[[
First release of Glass Forever, a fork of Glass by Mitchel Cabuloy (mixxorz), updated to work on WoW: Forever.

Bug fixes

- Fixed "secret number" errors when sizing messages and scrolling.
- Fixed blank chat after logging in.
- Fixed tabs going blank or overlapping after switching between them.
- Fixed whisper tabs failing or staying empty after being closed and re-opened.
- Fixed Combat Log text cut off at the left edge.

What's new

- Colored tab glow: a tab glows in the color of the chat type (guild green, party blue, and so on) when a message arrives and you're not looking at it.
- The tab bar appears for a few seconds when such a message arrives.
- A thin line above the selected tab.
    ]]}
  },
}
-- luacheck: pop

-- Text of the whole version history, one release after the other
local function HistoryText()
  local parts = {}
  for _, release in ipairs(CHANGELOG) do
    table.insert(parts, "|c00DFBA69"..release.name.."|r\n")
    for _, item in ipairs(release.items) do
      table.insert(parts, item)
    end
    table.insert(parts, "\n")
  end
  return table.concat(parts, "\n")
end

-- Window built with the game's own panel template (bronze border), like the
-- other Glass windows
local function CreateWindow()
  local frame = CreateFrame("Frame", "GlassNewsFrame", UIParent, "DefaultPanelFlatTemplate")
  frame:SetSize(600, 400)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetTitle("Glass Forever: Version history")
  frame:Hide()

  -- Close with the Escape key, like other game windows
  table.insert(_G.UISpecialFrames, "GlassNewsFrame")

  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetPoint("TOPLEFT", 7, -3)
  frame.bg:SetPoint("BOTTOMRIGHT", -3, 3)
  frame.bg:SetColorTexture(0.08, 0.08, 0.08, 1)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetFrameLevel((frame.TitleContainer or frame):GetFrameLevel() + 10)
  close:SetPoint("TOPRIGHT")

  local version = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  version:SetPoint("BOTTOMLEFT", 16, 10)
  version:SetText("Version: "..Core.Version)

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -32)
  scroll:SetPoint("BOTTOMRIGHT", -34, 28)

  local content = CreateFrame("Frame", nil, scroll)
  scroll:SetScrollChild(content)

  local text = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  text:SetPoint("TOPLEFT")
  text:SetJustifyH("LEFT")
  text:SetJustifyV("TOP")
  text:SetSpacing(3)
  text:SetText(HistoryText())

  -- Fit the text to the window width and let the scroll frame know its height
  local function Layout(width)
    content:SetWidth(width)
    text:SetWidth(width)
    content:SetHeight(text:GetStringHeight() + 10)
  end
  scroll:SetScript("OnSizeChanged", function (_, width) Layout(width) end)
  Layout(scroll:GetWidth())

  return frame
end

-- Module
function News:OnEnable()
  local window

  Core:Subscribe(OPEN_NEWS, function ()
    window = window or CreateWindow()
    window:Show()
  end)
end
