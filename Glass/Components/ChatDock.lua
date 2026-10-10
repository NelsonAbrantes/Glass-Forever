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

  -- Tabs can be dragged out of the dock to become separate chat windows, as in
  -- the default chat (see UIManager)

  self:QuickHide()

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
        end

        if key == "tabBarHeight" then
          self:UpdateHeight()
        end

        if key == "tabBarOpacity" then
          self:UpdateBackground()
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
