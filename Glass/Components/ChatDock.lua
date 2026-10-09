local Core, Constants = unpack(select(2, ...))

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
  self:SetHeight(Constants.DOCK_HEIGHT)
  self:ClearAllPoints()
  self:SetPoint("TOPLEFT", parent, "TOPLEFT")
  self:SetFadeInDuration(0.6)
  self:SetFadeOutDuration(0.6)

  self.scrollFrame:SetHeight(Constants.DOCK_HEIGHT)
  self.scrollFrame:SetPoint("TOPLEFT", _G.ChatFrame2Tab, "TOPRIGHT")
  self.scrollFrame.child:SetHeight(Constants.DOCK_HEIGHT)

  -- Gradient background
  local opacity = 0.4
  self:SetGradientBackground(50, 250, Colors.black, opacity)

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

          self:SetGradientBackground(50, 250, Colors.black, opacity)
        end
      end)
    }
  end
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
