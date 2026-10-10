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
        self:UpdateAlignment()
      end
    end)
  end
  self:UpdateAlignment()

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
