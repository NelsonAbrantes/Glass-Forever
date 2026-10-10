local Core, Constants = unpack(select(2, ...))

local AceHook = Core.Libs.AceHook

local MOUSE_ENTER = Constants.EVENTS.MOUSE_ENTER
local MOUSE_LEAVE = Constants.EVENTS.MOUSE_LEAVE
local UPDATE_CONFIG = Constants.EVENTS.UPDATE_CONFIG

-- luacheck: push ignore 113
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local hooksecurefunc = hooksecurefunc
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

-- Keeps a piece of the game's art hidden: the game shows it again when the
-- button changes state (e.g. after a click)
local function KeepHidden(region)
  region:SetAlpha(0)
  region:Hide()
  if region.glassHidden then return end
  region.glassHidden = true
  hooksecurefunc(region, "SetAlpha", function (_, alpha)
    if alpha ~= 0 then region:SetAlpha(0) end
  end)
  hooksecurefunc(region, "Show", function () region:Hide() end)
  hooksecurefunc(region, "SetShown", function (_, shown)
    if shown then region:Hide() end
  end)
end

-- Hides the game's art of a button (all its textures and its text, like the
-- friends count), including pieces the game adds later
local function Strip(button)
  for _, region in ipairs({ button:GetRegions() }) do
    if region ~= button.glassIcon then
      KeepHidden(region)
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
    -- A click can add new art: hide it once the game is done with the click
    button:HookScript("OnClick", function ()
      C_Timer.After(0, function () Strip(button) end)
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

-- Where the buttons go, for each "Position" option:
-- - holder: the point of the column (or row) and the point of the chat it
--   sits on, with the offset away from the chat
-- - first: the corner of the column/row where the first button goes
-- - next: how each button attaches to the one before it
-- - reverse: the row grows to the left, so it's laid out from the last button
--   to keep the same order on screen
local POSITIONS = {
  left = { holder = { "TOPRIGHT", "TOPLEFT", -MARGIN, 0 }, first = "TOPRIGHT",
    next = { "TOP", "BOTTOM", 0, -GAP } },
  right = { holder = { "TOPLEFT", "TOPRIGHT", MARGIN, 0 }, first = "TOPLEFT",
    next = { "TOP", "BOTTOM", 0, -GAP } },
  topleft = { holder = { "BOTTOMLEFT", "TOPLEFT", 0, MARGIN }, first = "BOTTOMLEFT",
    next = { "LEFT", "RIGHT", GAP, 0 } },
  topright = { holder = { "BOTTOMRIGHT", "TOPRIGHT", 0, MARGIN }, first = "BOTTOMRIGHT",
    next = { "RIGHT", "LEFT", -GAP, 0 }, reverse = true },
  bottomleft = { holder = { "TOPLEFT", "BOTTOMLEFT", 0, -MARGIN }, first = "TOPLEFT",
    next = { "LEFT", "RIGHT", GAP, 0 } },
  bottomright = { holder = { "TOPRIGHT", "BOTTOMRIGHT", 0, -MARGIN }, first = "TOPRIGHT",
    next = { "RIGHT", "LEFT", -GAP, 0 }, reverse = true },
}

local function Position()
  return POSITIONS[Core.db.profile.chatButtonsSide] or POSITIONS.left
end

---
-- Shows or hides the buttons and puts them in the chosen place
function ChatButtonsMixin:Update()
  local enabled = Core.db.profile.chatButtons
  local holder = Position().holder

  self:ClearAllPoints()
  self:SetPoint(holder[1], self.container, holder[2], holder[3], holder[4])

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
-- Lines up the shown buttons in a column (left and right of the chat) or a
-- row (above and below it), with no gaps
function ChatButtonsMixin:Layout()
  if self.layingOut then return end
  self.layingOut = true

  local position = Position()
  local shown = {}
  for _, button in ipairs(self.buttons) do
    if button:IsShown() then
      if position.reverse then
        table.insert(shown, 1, button)
      else
        table.insert(shown, button)
      end
    end
  end

  local nextPoint = position.next
  local previous
  for _, button in ipairs(shown) do
    button:ClearAllPoints()
    if previous then
      button:SetPoint(nextPoint[1], previous, nextPoint[2], nextPoint[3], nextPoint[4])
    else
      button:SetPoint(position.first, self, position.first, 0, 0)
    end
    previous = button
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
