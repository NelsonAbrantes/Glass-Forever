local Core, Constants = unpack(select(2, ...))

local AceHook = Core.Libs.AceHook

local MOUSE_ENTER = Constants.EVENTS.MOUSE_ENTER
local MOUSE_LEAVE = Constants.EVENTS.MOUSE_LEAVE
local UPDATE_CONFIG = Constants.EVENTS.UPDATE_CONFIG

-- luacheck: push ignore 113
local CreateFrame = CreateFrame
local Mixin = Mixin
-- luacheck: pop

-- The game's chat buttons, top to bottom, as in the default chat, with the
-- Glass icon each one gets. Some exist only in some clients, and the voice
-- ones only show while in a voice chat.
local BUTTONS = {
  { "QuickJoinToastButton", "buttonSocial" },             -- friends and social
  { "ChatFrameChannelButton", "buttonChannels" },         -- channels and voice chat
  { "ChatFrameToggleVoiceDeafenButton", "buttonDeafen" },
  { "ChatFrameToggleVoiceMuteButton", "buttonMute" },
  { "ChatFrameMenuButton", "buttonMenu" },                -- emotes, languages...
}

local ASSETS = "Interface\\Addons\\Glass\\Glass\\Assets\\"
local BUTTON_SIZE = 22
local ICON_SIZE = 16
local GAP = 2 -- space between the buttons
local MARGIN = 2 -- space between the buttons and the chat
local OFF_COLOR = { r = 1, g = 0.35, b = 0.3 } -- muted or deafened

----
-- ChatButtons
--
-- A column with the game's chat buttons beside Glass (Options > General >
-- Chat buttons). Off by default: Glass hides them. The buttons are the game's
-- own, moved here, so they work exactly as in the default chat. The column
-- appears and fades with the tab bar.
local ChatButtonsMixin = {}

function ChatButtonsMixin:Init(container)
  self.container = container
  self.state = {
    mouseOver = false
  }
  self:SetSize(1, 1)
  self:SetFadeInDuration(0.6)
  self:SetFadeOutDuration(0.6)

  self.buttons = {}
  for _, entry in ipairs(BUTTONS) do
    local button = _G[entry[1]]
    if button then
      table.insert(self.buttons, button)
      self:Restyle(button, entry[2])
      -- The voice buttons come and go: close the gap they leave
      self:SecureHook(button, "Show", function () self:Layout() end)
      self:SecureHook(button, "Hide", function () self:Layout() end)
    end
  end

  -- Muted and deafened show in red
  self:RegisterEvent("VOICE_CHAT_MUTED_CHANGED")
  self:RegisterEvent("VOICE_CHAT_DEAFENED_CHANGED")
  self:SetScript("OnEvent", function () self:UpdateColors() end)

  self:Update()

  if self.subscriptions == nil then
    self.subscriptions = {
      Core:Subscribe(MOUSE_ENTER, function ()
        self.state.mouseOver = true
        self:Show()
      end),
      Core:Subscribe(MOUSE_LEAVE, function ()
        self.state.mouseOver = false
        self:FadeOut()
      end),
      Core:Subscribe(UPDATE_CONFIG, function (key)
        if key == "chatButtons" or key == "chatButtonsSide" or key == "tabBarFade" then
          self:Update()
        end
      end)
    }
  end
end

-- Hides the game's art of a button (all its textures and its text, like the
-- friends count) and keeps it hidden when the game changes it
local function Strip(button)
  for _, region in ipairs({ button:GetRegions() }) do
    if region ~= button.glassIcon then
      region:SetAlpha(0)
    end
  end
end

local ART_METHODS = {
  "SetNormalTexture", "SetNormalAtlas", "SetPushedTexture", "SetPushedAtlas",
  "SetHighlightTexture", "SetHighlightAtlas", "SetDisabledTexture", "SetDisabledAtlas",
}

---
-- Gives a game button the Glass look: a plain icon in the Glass color, white
-- under the mouse. Only the look changes; clicks still go to the game's code.
function ChatButtonsMixin:Restyle(button, icon)
  button:SetSize(BUTTON_SIZE, BUTTON_SIZE)

  if button.glassIcon == nil then
    button.glassIcon = button:CreateTexture(nil, "OVERLAY", nil, 7)
    button.glassIcon:SetSize(ICON_SIZE, ICON_SIZE)
    button.glassIcon:SetPoint("CENTER")
    button.glassIcon:SetTexture(ASSETS..icon)

    -- The frame's own HookScript (secure): AceHook isn't embedded in it
    button:HookScript("OnEnter", function ()
      button.glassHover = true
      self:UpdateColors()
    end)
    button:HookScript("OnLeave", function ()
      button.glassHover = false
      self:UpdateColors()
    end)
    button:HookScript("OnMouseDown", function ()
      button.glassIcon:SetPoint("CENTER", 1, -1)
    end)
    button:HookScript("OnMouseUp", function ()
      button.glassIcon:SetPoint("CENTER")
    end)

    for _, method in ipairs(ART_METHODS) do
      if button[method] then
        self:SecureHook(button, method, Strip)
      end
    end
  end

  Strip(button)
  self:UpdateColors()
end

function ChatButtonsMixin:UpdateColors()
  local apache = Constants.COLORS.apache
  local voice = _G.C_VoiceChat
  for _, button in ipairs(self.buttons or {}) do
    local icon = button.glassIcon
    if icon then
      local off = voice and (
        (button == _G.ChatFrameToggleVoiceMuteButton and voice.IsMuted and voice.IsMuted()) or
        (button == _G.ChatFrameToggleVoiceDeafenButton and voice.IsDeafened and voice.IsDeafened())
      )
      if button.glassHover then
        icon:SetVertexColor(1, 1, 1)
      elseif off then
        icon:SetVertexColor(OFF_COLOR.r, OFF_COLOR.g, OFF_COLOR.b)
      else
        icon:SetVertexColor(apache.r, apache.g, apache.b)
      end
    end
  end
end

-- Hides the column like the tab bar, unless the tab bar's "Fade out" is off
function ChatButtonsMixin:FadeOut()
  if Core.db.profile.tabBarFade == false then return end
  if Core.db.profile.chatShowOnMouseOver then
    self:HideDelay(Core.db.profile.chatHoldTime)
  else
    self:Hide()
  end
end

---
-- Shows or hides the buttons and puts them on the chosen side
function ChatButtonsMixin:Update()
  local enabled = Core.db.profile.chatButtons
  local left = Core.db.profile.chatButtonsSide ~= "right"

  self:ClearAllPoints()
  if left then
    self:SetPoint("TOPRIGHT", self.container, "TOPLEFT", -MARGIN, 0)
  else
    self:SetPoint("TOPLEFT", self.container, "TOPRIGHT", MARGIN, 0)
  end

  for _, button in ipairs(self.buttons) do
    if enabled then
      button:SetParent(self)
    else
      button:SetParent(self.hiddenParent)
    end
  end

  if enabled and (self.state.mouseOver or Core.db.profile.tabBarFade == false) then
    self:QuickShow()
  elseif enabled and self:IsShown() then
    self:FadeOut()
  else
    self:QuickHide()
  end

  self:Layout()
end

---
-- Stacks the shown buttons from the top, with no gaps
function ChatButtonsMixin:Layout()
  if self.layingOut then return end
  self.layingOut = true

  local left = Core.db.profile.chatButtonsSide ~= "right"
  local point = left and "TOPRIGHT" or "TOPLEFT"
  local previous
  for _, button in ipairs(self.buttons) do
    if button:IsShown() then
      button:ClearAllPoints()
      if previous then
        button:SetPoint("TOP", previous, "BOTTOM", 0, -GAP)
      else
        button:SetPoint(point, self, point, 0, 0)
      end
      previous = button
    end
  end

  self.layingOut = false
end

---
-- True while the mouse is over one of the shown buttons, so moving from the
-- chat to the buttons doesn't count as leaving the chat
function ChatButtonsMixin:IsMouseOverButtons()
  if not self:IsShown() then return false end
  for _, button in ipairs(self.buttons) do
    if button:IsVisible() and button:IsMouseOver() then
      return true
    end
  end
  return false
end

Core.Components.CreateChatButtons = function (container)
  local FadingFrameMixin = Core.Components.FadingFrameMixin

  local frame = CreateFrame("Frame", "GlassChatButtons", container:GetParent())
  local object = Mixin(frame, FadingFrameMixin, ChatButtonsMixin)
  AceHook:Embed(object)

  -- Where the buttons go while the option is off: a frame that's never shown
  object.hiddenParent = CreateFrame("Frame", nil, frame)
  object.hiddenParent:Hide()

  FadingFrameMixin.Init(object)
  ChatButtonsMixin.Init(object, container)
  return object
end
