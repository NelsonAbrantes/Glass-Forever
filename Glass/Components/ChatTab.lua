local Core, Constants, Utils = unpack(select(2, ...))

local AceHook = Core.Libs.AceHook

local UnlockMover = Constants.ACTIONS.UnlockMover

local Colors = Constants.COLORS

local UPDATE_CONFIG = Constants.EVENTS.UPDATE_CONFIG

-- luacheck: push ignore 113
local DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME
local ChatTypeInfo = ChatTypeInfo
local FCF_StopAlertFlash = FCF_StopAlertFlash
local GetPhysicalScreenSize = GetPhysicalScreenSize
local IsCombatLog = IsCombatLog
local Mixin = Mixin
local UNLOCK_WINDOW = UNLOCK_WINDOW
-- luacheck: pop

local tabTexs = {
  "Left", "Middle", "Right",
  "ActiveLeft", "ActiveMiddle", "ActiveRight",
  "HighlightLeft", "HighlightMiddle", "HighlightRight"
}

local ChatTabMixin = {}

function ChatTabMixin:Init(slidingMessageFrame)
  self.slidingMessageFrame = slidingMessageFrame
  self.chatFrame = slidingMessageFrame.chatFrame

  for _, texName in ipairs(tabTexs) do
    self[texName]:SetTexture(nil)
  end

  self:SetNormalFontObject("GlassChatDockFont")
  self:UpdateLayout()

  -- All hooks below are secure: they run after the game's code and correct
  -- what it did, instead of replacing its functions. Replacing taints the
  -- game's chat code (tabs are updated while messages arrive), which then fails
  -- on "secret" messages. self.adjusting stops a correction from re-triggering
  -- its own hook.
  local function Adjust(fn)
    if self.adjusting then return end
    self.adjusting = true
    pcall(fn)
    self.adjusting = false
  end

  -- Tabs never fade
  if not self:IsHooked(self, "SetAlpha") then
    self:SecureHook(self, "SetAlpha", function (_, alpha)
      if alpha ~= 1 then
        Adjust(function () self:SetAlpha(1) end)
      end
    end)
  end

  -- Set width dynamically based on text width
  if not self:IsHooked(self, "SetWidth") then
    self:SecureHook(self, "SetWidth", function ()
      local padding = Utils.TabPadding()
      local width = self:FitText() + padding * 2

      -- When the tabs don't fit on the bar, some get narrower (see the dock's
      -- TabLayout): first with less space around the name, then with "..."
      local dock = _G.GeneralDockManager
      local shrunkWidth, exact
      if dock.DynamicTabWidth then
        shrunkWidth, exact = dock:DynamicTabWidth(self)
      end
      local textLeft = padding
      if shrunkWidth and (exact or shrunkWidth < width) then
        local minPadding = Constants.TAB_SHRUNK_PADDING
        -- Whisper tabs keep room for their icon, left of the name
        local icon = self.conversationIcon
        local iconWidth = icon and icon:IsShown() and icon:GetWidth() or 0
        local spare = shrunkWidth - (width - padding * 2) - iconWidth
        textLeft = iconWidth + math.max(minPadding, math.min(padding, spare / 2))
        self.Text:SetWidth(math.max(1, shrunkWidth - textLeft - minPadding))
        width = shrunkWidth
      end
      if self.textLeft ~= textLeft then
        self.textLeft = textLeft
        self.Text:ClearAllPoints()
        self.Text:SetPoint("LEFT", textLeft, 0)
      end

      if math.abs(self:GetWidth() - width) > 0.5 then
        Adjust(function () self:SetWidth(width) end)
      end
      -- Wider or narrower tabs move the others when centered or on the right
      if dock.UpdateAlignment then
        dock:UpdateOverflow()
        dock:UpdateAlignment()
      end
    end)
  end

  if not self:IsHooked(self.Text, "SetTextColor") then
    self:SecureHook(self.Text, "SetTextColor", function ()
      -- Temporary chat frames retain their color
      if not self.chatFrame.isTemporary then
        Adjust(function ()
          self.Text:SetTextColor(Colors.apache.r, Colors.apache.g, Colors.apache.b)
        end)
      end
    end)
  end

  -- Don't highlight when frame is already visible
  if not self:IsHooked(self.glow, "Show") then
    self:SecureHook(self.glow, "Show", function ()
      -- self.slidingMessageFrame, not the Init argument: temporary tabs are
      -- reused for new whispers with a different frame
      if self.slidingMessageFrame:IsVisible() then
        self.glow:Hide()
        return
      end

      -- Tint the glow with the color of the chat type that triggered it.
      -- Desaturate first, otherwise the texture's own tint mixes with the color.
      local color = self.glowColor
      if color then
        self.glow:SetDesaturated(true)
        Adjust(function () self.glow:SetVertexColor(color.r, color.g, color.b) end)
      else
        self.glow:SetDesaturated(false)
      end
    end)
  end

  -- Keep the glow fully visible while it's lit with a chat type color. The game
  -- animates whisper alerts by fading the glow, which ended up invisible.
  if not self:IsHooked(self.glow, "SetAlpha") then
    self:SecureHook(self.glow, "SetAlpha", function (_, alpha)
      if self.glowColor and self.glow:IsShown() and alpha ~= 1 then
        Adjust(function () self.glow:SetAlpha(1) end)
      end
    end)
  end

  -- Keep the glow in the chat type color even if Blizzard resets it
  if not self:IsHooked(self.glow, "SetVertexColor") then
    self:SecureHook(self.glow, "SetVertexColor", function ()
      local color = self.glowColor
      if color then
        Adjust(function () self.glow:SetVertexColor(color.r, color.g, color.b) end)
      end
    end)
  end

  -- Un-highlight when clicked. Uses the frame's own HookScript (secure): the
  -- AceHook methods embedded in this tab hide it under the same name.
  if not self.glassClickHooked then
    self.glassClickHooked = true
    getmetatable(self).__index.HookScript(self, "OnClick", function ()
      FCF_StopAlertFlash(self.chatFrame)
    end)
  end

  -- Disable dragging for General and CombatLog
  if self.chatFrame == DEFAULT_CHAT_FRAME or IsCombatLog(self.chatFrame) then
    self:RegisterForDrag()
  end

  if self.chatFrame == DEFAULT_CHAT_FRAME then
    _G.Menu.ModifyMenu("MENU_FCF_TAB", function (owner, rootDescription)
      if owner == self then
        rootDescription:CreateButton(UNLOCK_WINDOW, function ()
          Core:Dispatch(UnlockMover())
        end)
      end
    end)
  end

  -- Thin line above the tab, shown only while this tab is selected.
  -- Size and thickness are set in UpdateSelected.
  if self.selectedLine == nil then
    self.selectedLine = self:CreateTexture(nil, "OVERLAY")
    self.selectedLine:SetColorTexture(Colors.apache.r, Colors.apache.g, Colors.apache.b, 1)
    self:PlaceSelectedLine()
    self.selectedLine:SetSize(1, 1)
    self.selectedLine:Hide()
  end

  -- Listeners
  if self.subscriptions == nil then
    self.subscriptions = {
      Core:Subscribe(UPDATE_CONFIG, function (key)
        if key == "frameWidth" or key == "frameHeight" or key == "font" or key == "messageFontSize"
          or key == "tabFont" or key == "tabFontSize" or key == "tabBarHeight" or key == "tabPadding"
          or key == "tabBarPosition" then
          -- Fit the tab to its text, the bar height and the spacing
          self:UpdateLayout()
        end
      end)
    }
  end
end

---
-- Height, text position and width of the tab, from the Tabs options
function ChatTabMixin:UpdateLayout()
  local padding = Utils.TabPadding()
  self:SetHeight(Utils.TabBarHeight())
  -- The name's position is set in the SetWidth hook (it moves when the tab is
  -- shrunk to fit the bar)
  self.textLeft = nil
  self:SetWidth(self:FitText() + padding * 2)
  self:PlaceSelectedLine()
end

---
-- The selected line sits on the side facing the messages: above the tab, or
-- below it when the tab bar is at the bottom
function ChatTabMixin:PlaceSelectedLine()
  local line = self.selectedLine
  if line == nil then return end
  line:ClearAllPoints()
  if Utils.TabBarAtBottom() then
    line:SetPoint("BOTTOM", self, "BOTTOM", 0, 0)
  else
    line:SetPoint("TOP", self, "TOP", 0, 0)
  end
end

---
-- Gives the tab name room for its full width and returns that width. The game
-- limits the width of tab names and cuts long ones ("Combat L..."); measuring
-- the cut text made the tab too narrow.
function ChatTabMixin:FitText()
  local width = self:FullTextWidth()
  if math.abs(self.Text:GetWidth() - width) > 0.5 then
    self.Text:SetWidth(width)
  end
  return width
end

---
-- Width of the whole tab name, even when it's shown cut
function ChatTabMixin:FullTextWidth()
  local width = self.Text.GetUnboundedStringWidth and self.Text:GetUnboundedStringWidth() or self:GetTextWidth()
  if issecretvalue and issecretvalue(width) then
    return self:GetTextWidth()
  end
  return math.ceil(width) + 1
end

---
-- Lights the glow steadily in the given chat type color (no flashing)
function ChatTabMixin:ShowSteadyGlow(color)
  local glow = self.glow
  self.glowColor = color

  -- Stop any flash the game started on it
  if _G.UIFrameFlashStop then
    _G.UIFrameFlashStop(glow)
  end
  if glow.GetAnimationGroups then
    for _, group in ipairs({ glow:GetAnimationGroups() }) do
      group:Stop()
    end
  end

  glow:Show()
  glow:SetAlpha(1)
end

local LINE_THICKNESS_PIXELS = 2 -- thickness of the selected-tab line, in real screen pixels
local LINE_WIDTH_RATIO = 0.5    -- fraction of the tab width

function ChatTabMixin:UpdateSelected(selected)
  local line = self.selectedLine
  if line == nil then return end

  local isSelected = (self.chatFrame == selected)

  if isSelected then
    -- Convert real pixels to this tab's own units, so every tab gets the same thickness.
    -- This runs every frame, so only resize when something changed.
    local _, screenHeight = GetPhysicalScreenSize()
    local scale = self:GetEffectiveScale()
    if screenHeight and screenHeight > 0 and scale and scale > 0 then
      local height = LINE_THICKNESS_PIXELS * (768 / screenHeight) / scale
      if line.glassHeight ~= height then
        line.glassHeight = height
        line:SetHeight(height)
      end
    end
    local width = self:GetWidth() * LINE_WIDTH_RATIO
    if line.glassWidth ~= width then
      line.glassWidth = width
      line:SetWidth(width)
    end
  end

  if line:IsShown() ~= isSelected then
    line:SetShown(isSelected)
  end
end

Core.Components.CreateChatTab = function (slidingMessageFrame)
  local frame = _G[slidingMessageFrame.chatFrame:GetName().."Tab"]
  local object = Mixin(frame, ChatTabMixin)
  AceHook:Embed(object)
  object:Init(slidingMessageFrame)
  return object
end