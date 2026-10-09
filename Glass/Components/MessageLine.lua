local Core, Constants = unpack(select(2, ...))

local Colors = Constants.COLORS

local HyperlinkClick = Constants.ACTIONS.HyperlinkClick
local HyperlinkEnter = Constants.ACTIONS.HyperlinkEnter
local HyperlinkLeave = Constants.ACTIONS.HyperlinkLeave

local UPDATE_CONFIG = Constants.EVENTS.UPDATE_CONFIG

-- luacheck: push ignore 113
local CreateFrame = CreateFrame
local CreateObjectPool = CreateObjectPool
local Mixin = Mixin
-- luacheck: pop

local MessageLineMixin = {}

----
-- Line count estimation
--
-- Retail 12.x can hide the real height of a message ("secret" values). When
-- that happens we count the lines ourselves: a hidden font string with the same
-- font measures each word, and we simulate the word wrap.
local measureString

local function GetMeasureString()
  if measureString == nil then
    local frame = CreateFrame("Frame", nil, _G.UIParent)
    frame:Hide()
    measureString = frame:CreateFontString(nil, "ARTWORK", "GlassMessageFont")
  end
  return measureString
end

-- Width of a piece of text, or nil if the game hides it
local function MeasureWidth(text)
  local fs = GetMeasureString()
  fs:SetText(text)
  local width = fs:GetUnboundedStringWidth()
  if issecretvalue and issecretvalue(width) then
    return nil
  end
  return width
end

-- Removes formatting codes, keeping only the text that is drawn
local function VisibleText(text)
  text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
  text = text:gsub("|cn.-:", "")
  text = text:gsub("|r", "")
  text = text:gsub("|H.-|h(.-)|h", "%1")
  text = text:gsub("|T.-|t", "MM") -- inline icons take about two letters
  text = text:gsub("|A.-|a", "MM")
  text = text:gsub("||", "|")
  return text
end

-- Number of lines the text needs at the given width, or nil if unknown
local function EstimateNumLines(text, width)
  if text == nil or width <= 0 then return nil end
  if issecretvalue and issecretvalue(text) then return nil end

  local visible = VisibleText(text)

  local total = MeasureWidth(visible)
  if total == nil then return nil end
  if total <= width then return 1 end

  local lines, lineWidth = 1, 0
  for word in visible:gmatch("%S+%s*") do
    -- The space after a word doesn't count when the word ends a line
    local bareWidth = MeasureWidth(word:match("^%S+"))
    local wordWidth = MeasureWidth(word)
    if bareWidth == nil or wordWidth == nil then return nil end

    if lineWidth > 0 and lineWidth + bareWidth > width then
      lines = lines + 1
      lineWidth = 0
    end

    -- A single word longer than the line is broken across lines
    while wordWidth > width do
      lines = lines + 1
      wordWidth = wordWidth - width
    end

    lineWidth = lineWidth + wordWidth
  end

  return lines
end

function MessageLineMixin:Init()
  self:SetWidth(Core.db.profile.frameWidth)
  self:SetFadeInDuration(Core.db.profile.chatFadeInDuration)
  self:SetFadeOutDuration(Core.db.profile.chatFadeOutDuration)

  local rightBgWidth = math.min(250, Core.db.profile.frameWidth - 50)
  self:SetGradientBackground(50, rightBgWidth, Colors.codGray, Core.db.profile.chatBackgroundOpacity)

  if self.text == nil then
    self.text = self:CreateFontString(nil, "ARTWORK", "GlassMessageFont")
  end
  self.text:SetPoint("LEFT", Constants.TEXT_XPADDING, 0)
  self.text:SetWidth(Core.db.profile.frameWidth - Constants.TEXT_XPADDING * 2)
  self.text:SetIndentedWordWrap(Core.db.profile.indentWordWrap)

  -- Hyperlink handling
  self:SetHyperlinksEnabled(true)

  self:SetScript("OnHyperlinkClick", function (_, link, text, button)
    Core:Dispatch(HyperlinkClick({link, text, button}))
  end)

  self:SetScript("OnHyperlinkEnter", function (_, link, text)
    if Core.db.profile.mouseOverTooltips then
      Core:Dispatch(HyperlinkEnter({link, text}))
    end
  end)

  self:SetScript("OnHyperlinkLeave", function (_, link)
    Core:Dispatch(HyperlinkLeave(link))
  end)

  if self.subscriptions == nil then
    self.subscriptions = {
      Core:Subscribe(UPDATE_CONFIG, function (key)
        if key == "chatFadeInDuration" then
          self:SetFadeInDuration(Core.db.profile.chatFadeInDuration)
        end

        if key == "chatFadeOutDuration" then
          self:SetFadeOutDuration(Core.db.profile.chatFadeOutDuration)
        end
      end)
    }
  end
end

---
-- Update height based on text height
function MessageLineMixin:UpdateFrame()
  local Ypadding = self.text:GetLineHeight() * Core.db.profile.messageLinePadding
  local stringHeight = self.text:GetStringHeight()
  -- Retail 12.x: GetStringHeight can return a "secret" value that addons cannot
  -- do arithmetic on. Fall back to the line count: the game's own if it shares
  -- it, otherwise our estimate, otherwise a single line.
  if issecretvalue and issecretvalue(stringHeight) then
    local lineHeight = self.text:GetLineHeight()
    local numLines = self.text.GetNumLines and self.text:GetNumLines()
    if not numLines or issecretvalue(numLines) or numLines < 1 then
      local textWidth = Core.db.profile.frameWidth - Constants.TEXT_XPADDING * 2
      numLines = EstimateNumLines(self.text:GetText(), textWidth) or 1
    end
    stringHeight = lineHeight * numLines + Core.db.profile.messageLeading * (numLines - 1)
  end
  local messageLineHeight = (stringHeight + Ypadding * 2)
  self:SetHeight(messageLineHeight)

  self:SetWidth(Core.db.profile.frameWidth)
  self.text:SetWidth(Core.db.profile.frameWidth - Constants.TEXT_XPADDING * 2)
  self.text:SetIndentedWordWrap(Core.db.profile.indentWordWrap)

  local rightBgWidth = math.min(250, Core.db.profile.frameWidth - 50)
  self:SetGradientBackground(50, rightBgWidth, Colors.codGray, Core.db.profile.chatBackgroundOpacity)
end

---
-- Update texture color based on setting
function MessageLineMixin:UpdateTextures()
  local rightBgWidth = math.min(250, Core.db.profile.frameWidth - 50)
  self:SetGradientBackground(50, rightBgWidth, Colors.codGray, Core.db.profile.chatBackgroundOpacity)
end

local function CreateMessageLine(parent)
  local FadingFrameMixin = Core.Components.FadingFrameMixin
  local GradientBackgroundMixin = Core.Components.GradientBackgroundMixin

  local frame = CreateFrame("Frame", nil, parent)
  local object = Mixin(frame, FadingFrameMixin, GradientBackgroundMixin, MessageLineMixin)

  FadingFrameMixin.Init(object)
  GradientBackgroundMixin.Init(object)
  MessageLineMixin.Init(object)

  return object
end

local function CreateMessageLinePool(parent)
  return CreateObjectPool(
    function () return CreateMessageLine(parent) end,
    function (_, message)
      -- Reset all animations and timers
      message:QuickHide()
    end
  )
end

Core.Components.CreateMessageLine = CreateMessageLine
Core.Components.CreateMessageLinePool = CreateMessageLinePool
