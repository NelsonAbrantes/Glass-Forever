local Core, Constants, Utils = unpack(select(2, ...))

local AceHook = Core.Libs.AceHook

local Colors = Constants.COLORS

local MOUSE_ENTER = Constants.EVENTS.MOUSE_ENTER
local MOUSE_LEAVE = Constants.EVENTS.MOUSE_LEAVE
local UPDATE_CONFIG = Constants.EVENTS.UPDATE_CONFIG

-- luacheck: push ignore 113
local Mixin = Mixin
local GeneralDockManager = GeneralDockManager
-- luacheck: pop

local ChatDockMixin = {}

function ChatDockMixin:Init(parent)
  self.state = {
    mouseOver = false
  }

  self:SetWidth(Core.db.profile.frameWidth)
  self.container = parent
  self:UpdatePosition()
  self:SetFadeInDuration(0.6)
  self:SetFadeOutDuration(0.6)

  self.scrollFrame:SetPoint("TOPLEFT", _G.ChatFrame2Tab, "TOPRIGHT")

  -- Height and background opacity come from the Tabs options
  self:UpdateHeight()
  self:UpdateBackground()

  -- The game lines the tabs up from the left whenever they change (a tab opens,
  -- closes or is moved); move them to the chosen alignment afterwards
  if _G.FCFDock_UpdateTabs and not self:IsHooked("FCFDock_UpdateTabs") then
    self:SecureHook("FCFDock_UpdateTabs", function (dock)
      if dock == self then
        -- Whisper tabs share the room left on the bar, which just changed
        for _, chatFrame in ipairs(self.DOCKED_CHAT_FRAMES or {}) do
          local tab = _G[chatFrame:GetName().."Tab"]
          if tab and tab.UpdateLayout then
            tab:UpdateLayout()
          end
        end
        self:UpdateOverflow()
        self:UpdateAlignment()
      end
    end)
  end
  self:UpdateAlignment()

  -- While the tabs all fit, the game must not scroll them (it would hide the
  -- first ones, see UpdateOverflow)
  if not self:IsHooked(self.scrollFrame, "SetHorizontalScroll") then
    self:SecureHook(self.scrollFrame, "SetHorizontalScroll", function (_, offset)
      if self.tabsOverflow == false and offset ~= 0 and not self.resettingScroll then
        self.resettingScroll = true
        self.scrollFrame:SetHorizontalScroll(0)
        self.resettingScroll = false
      end
    end)
  end

  -- Tabs can be dragged out of the dock to become separate chat windows, as in
  -- the default chat (see UIManager)

  -- Hidden until the mouse is over the chat, unless "Fade out" is off
  if Core.db.profile.tabBarFade == false then
    self:QuickShow()
  else
    self:QuickHide()
  end

  if self.subscriptions == nil then
    self.subscriptions = {
      Core:Subscribe(MOUSE_ENTER, function ()
        -- Don't hide tabs when mouse is over
        self.state.mouseOver = true
        self:Show()
      end),
      Core:Subscribe(MOUSE_LEAVE, function ()
        -- Hide chat tab when mouse leaves
        self.state.mouseOver = false

        -- "Fade out" turned off in the Tabs options: the tab bar stays
        if Core.db.profile.tabBarFade == false then return end

        if Core.db.profile.chatShowOnMouseOver then
          -- When chatShowOnMouseOver is on, synchronize the chat tab's fade out with
          -- the chat
          self:HideDelay(Core.db.profile.chatHoldTime)
        else
          -- Otherwise hide it immediately on mouse leave
          self:Hide()
        end
      end),
      Core:Subscribe(UPDATE_CONFIG, function (key)
        if key == "frameWidth" then
          self:SetWidth(Core.db.profile.frameWidth)
          self:UpdateBackground()
          self:UpdateAlignment()
        end

        if key == "tabAlign" then
          self:UpdateAlignment()
        end

        if key == "tabBarHeight" then
          self:UpdateHeight()
        end

        if key == "tabBarOpacity" then
          self:UpdateBackground()
        end

        if key == "tabBarFade" then
          if Core.db.profile.tabBarFade == false then
            self:Show()
          elseif not self.state.mouseOver then
            self:HideDelay(Core.db.profile.chatHoldTime)
          end
        end

        if key == "tabBarPosition" or key == "tabBarOffsetX" or key == "tabBarOffsetY" then
          self:UpdatePosition()
        end
      end)
    }
  end
end

---
-- Puts the tab bar above or below the messages (Tabs options)
function ChatDockMixin:UpdatePosition()
  -- Plus a fine adjustment in pixels (positive X = right, positive Y = up)
  local x = Core.db.profile.tabBarOffsetX or 0
  local y = Core.db.profile.tabBarOffsetY or 0
  self:ClearAllPoints()
  if Utils.TabBarAtBottom() then
    self:SetPoint("BOTTOMLEFT", self.container, "BOTTOMLEFT", x, y)
  else
    self:SetPoint("TOPLEFT", self.container, "TOPLEFT", x, y)
  end
end

---
-- Places the tabs on the left, center or right of the tab bar (Tabs options).
-- The game anchors the first tab to the left of the bar and every other tab to
-- the one before it, so moving the first tab moves them all.
function ChatDockMixin:UpdateAlignment()
  local frames = self.DOCKED_CHAT_FRAMES
  if not frames or not frames[1] then return end

  local first = _G[frames[1]:GetName().."Tab"]
  if not first or first:GetNumPoints() == 0 then return end

  local point, relativeTo, relativePoint, _, y = first:GetPoint(1)
  if relativeTo ~= self then return end

  -- Total width of the tabs
  local tabsWidth = 0
  for _, chatFrame in ipairs(frames) do
    local tab = _G[chatFrame:GetName().."Tab"]
    if tab and tab:IsShown() then
      tabsWidth = tabsWidth + tab:GetWidth()
    end
  end

  -- When the tabs don't fit, they stay on the left (the game scrolls them).
  -- 1px to spare, so the game never thinks they're too wide.
  local free = math.max(0, self:GetWidth() - tabsWidth - 1)
  local x = 0
  if Core.db.profile.tabAlign == "center" then
    x = math.floor(free / 2)
  elseif Core.db.profile.tabAlign == "right" then
    x = math.floor(free)
  end

  first:SetPoint(point, relativeTo, relativePoint, x, y)
end

local MIN_TAB_WIDTH = 50 -- smallest a tab gets before the game's arrow appears

---
-- Widest the tabs in a list can be to share `room`, or nil if they all fit at
-- their full width. Narrowest first: each one that fits in an equal share
-- keeps its width, and the wider ones share what's left.
local function ShareRoom(widths, room)
  table.sort(widths)
  local left = #widths
  for _, width in ipairs(widths) do
    local share = room / left
    if width > share then
      return math.floor(share)
    end
    room = room - width
    left = left - 1
  end
  return nil
end

local function Sum(widths)
  local total = 0
  for _, width in ipairs(widths) do
    total = total + width
  end
  return total
end

---
-- Decides how wide the tabs in the bar's scrolling part are. That part comes
-- after General and Combat Log (which never change) and holds the other chats
-- (Guild, Party, Trade...) and the whisper tabs; anything past the end of the
-- bar is cut off. When they don't fit, in this order:
-- 1. Less space around the names (down to SHRUNK_PADDING), full names.
-- 2. Whisper names get "...": they come and go. Down to MIN_TAB_WIDTH.
-- 3. Then the other chats' names, down to MIN_TAB_WIDTH too.
-- 4. If even that doesn't fit, the game's own system takes over: all those
--    tabs the same width, and an arrow at the end of the bar with the list of
--    chats.
-- Returns overflow (true in case 4) and the width of each shrunk tab (tabs
-- not in the list keep their normal width).
function ChatDockMixin:TabLayout()
  local scrollChild = self.scrollFrame and self.scrollFrame.child
  local padding = Utils.TabPadding()
  local SHRUNK_PADDING = Constants.TAB_SHRUNK_PADDING
  local fixedWidth = 0
  local tabs = {} -- { tab, full width, compact width, is whisper }
  local count = 0

  for _, chatFrame in ipairs(self.DOCKED_CHAT_FRAMES or {}) do
    local tab = _G[chatFrame:GetName().."Tab"]
    if tab then
      count = count + 1
      local text = tab.FullTextWidth and tab:FullTextWidth() or tab:GetWidth() - padding * 2
      if tab:GetParent() ~= scrollChild then
        fixedWidth = fixedWidth + text + padding * 2
      else
        local icon = tab.conversationIcon
        local iconWidth = icon and icon:IsShown() and icon:GetWidth() or 0
        local full = text + padding * 2
        local compact = math.min(full, text + SHRUNK_PADDING * 2 + iconWidth)
        table.insert(tabs, { tab, full, compact, chatFrame.isTemporary })
      end
    end
  end

  -- The game leaves 1px between tabs
  local room = self:GetWidth() - fixedWidth - count
  local widths = {}

  local fullSum, compactSum, chatCompactSum, numWhispers = 0, 0, 0, 0
  for _, entry in ipairs(tabs) do
    fullSum = fullSum + entry[2]
    compactSum = compactSum + entry[3]
    if entry[4] then
      numWhispers = numWhispers + 1
    else
      chatCompactSum = chatCompactSum + entry[3]
    end
  end

  -- Everything fits
  if fullSum <= room then
    return false, widths
  end

  -- 1. Full names with less space around them, sharing the extra room evenly
  if compactSum <= room then
    local extra = (room - compactSum) / #tabs
    for _, entry in ipairs(tabs) do
      widths[entry[1]] = math.floor(math.min(entry[2], entry[3] + extra))
    end
    return false, widths
  end

  -- Shrinks the names of one group of tabs to share `groupRoom`
  local function Shrink(isWhisper, groupRoom)
    local list = {}
    for _, entry in ipairs(tabs) do
      if (entry[4] and true or false) == isWhisper then
        table.insert(list, entry[3])
      end
    end
    local cap = ShareRoom(list, groupRoom)
    for _, entry in ipairs(tabs) do
      if (entry[4] and true or false) == isWhisper then
        widths[entry[1]] = cap and math.min(entry[3], cap) or entry[3]
      end
    end
  end

  -- 2. Chats with their full names, whispers share the rest
  if chatCompactSum + numWhispers * MIN_TAB_WIDTH <= room then
    Shrink(false, chatCompactSum)
    Shrink(true, room - chatCompactSum)
    return false, widths
  end

  -- 3. Whispers at their smallest, chats share the rest
  local chatsRoom = room - numWhispers * MIN_TAB_WIDTH
  if (#tabs - numWhispers) * MIN_TAB_WIDTH <= chatsRoom then
    Shrink(true, numWhispers * MIN_TAB_WIDTH)
    Shrink(false, chatsRoom)
    return false, widths
  end

  return true, widths
end

---
-- Width a tab in the scrolling part must have, or nil to keep its normal
-- width. The second value is true when the game picked it (exactly that
-- width, even when wider than the name)
function ChatDockMixin:DynamicTabWidth(tab)
  local scrollChild = self.scrollFrame and self.scrollFrame.child
  if not scrollChild or tab:GetParent() ~= scrollChild then return nil end

  local overflow, widths = self:TabLayout()
  if overflow then
    -- The size the game picked: its scrolling counts on every tab having it
    return self.scrollFrame.dynTabSize, true
  end
  return widths[tab]
end

---
-- The game shows its arrow (and scrolls the tabs) by its own count, which
-- assumes small tabs of the same size. When our tabs all fit, hide the arrow,
-- give the tabs the whole bar and keep them from scrolling.
function ChatDockMixin:UpdateOverflow()
  local overflow = self:TabLayout()
  self.tabsOverflow = overflow
  if overflow then return end

  if self.overflowButton and self.overflowButton:IsShown() then
    self.overflowButton:Hide()
    self.scrollFrame:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, -1)
  end
  if self.scrollFrame:GetHorizontalScroll() ~= 0 then
    self.scrollFrame:SetHorizontalScroll(0)
  end
end

function ChatDockMixin:UpdateHeight()
  local height = Utils.TabBarHeight()
  self:SetHeight(height)
  self.scrollFrame:SetHeight(height)
  self.scrollFrame.child:SetHeight(height)
end

function ChatDockMixin:UpdateBackground()
  self:SetGradientBackground(50, 250, Colors.black, Core.db.profile.tabBarOpacity or 0.4)
end

local isCreated = false

Core.Components.CreateChatDock = function (parent)
  if isCreated then
    error("ChatDock already exists. Only one ChatDock can exist at a time.")
  end

  local FadingFrameMixin = Core.Components.FadingFrameMixin
  local GradientBackgroundMixin = Core.Components.GradientBackgroundMixin

  isCreated = true
  local object = Mixin(GeneralDockManager, FadingFrameMixin, GradientBackgroundMixin, ChatDockMixin)
  AceHook:Embed(object)
  FadingFrameMixin.Init(object)
  GradientBackgroundMixin.Init(object)
  ChatDockMixin.Init(object, parent)
  return object
end
