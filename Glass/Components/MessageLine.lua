local Core, Constants = unpack(select(2, ...))

local Colors = Constants.COLORS

local HyperlinkClick = Constants.ACTIONS.HyperlinkClick
local HyperlinkEnter = Constants.ACTIONS.HyperlinkEnter
local HyperlinkLeave = Constants.ACTIONS.HyperlinkLeave

local UPDATE_CONFIG = Constants.EVENTS.UPDATE_CONFIG

-- luacheck: push ignore 113
local CreateColor = CreateColor
local CreateFrame = CreateFrame
local CreateObjectPool = CreateObjectPool
local hooksecurefunc = hooksecurefunc
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

-- Widths already measured, so busy chats don't measure the same words over
-- and over. Emptied when the font changes, or when it gets large.
local widthCache, cacheSize, cacheFont = {}, 0, nil
local MAX_CACHE = 4000

-- Width of a piece of text, or nil if the game hides it
local function MeasureWidth(text)
  local fs = GetMeasureString()

  local file, size, flags = fs:GetFont()
  local font = tostring(file)..tostring(size)..tostring(flags)
  if font ~= cacheFont or cacheSize > MAX_CACHE then
    widthCache, cacheSize, cacheFont = {}, 0, font
  end

  local cached = widthCache[text]
  if cached then return cached end

  fs:SetText(text)
  local width = fs:GetUnboundedStringWidth()
  if issecretvalue and issecretvalue(width) then
    return nil
  end

  widthCache[text] = width
  cacheSize = cacheSize + 1
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
    Core:Dispatch(HyperlinkClick({link, text, button, self.chatFrame}))
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
  -- The background above shows again: the separator keeps its own look
  if self.isSeparator then self:SetSeparator(true) end
end

---
-- The "Previous session" separator (History module): its text centered and
-- smaller-looking in a dim gold, with a thin line on each side that fades out
-- towards the edge, and no message background. Lines are textures, so they
-- don't depend on the font having line characters.
local SEPARATOR_GAP = 8      -- between the text and each line
local SEPARATOR_ALPHA = 0.55 -- the lines at their strongest, next to the text

-- The separator's text, or nil if this isn't one. Older versions saved it as
-- "-------- Previous session, ended 12 Oct, 14:30 --------". A separate
-- window's copy (between dashes, or images in a test version), brought back by the
-- game after a reload, is one too.
local function SeparatorText(text)
  if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return nil end
  if not text:find("Previous session", 1, true) then return nil end
  local core = text:match("^%-*%s*(Previous session.-)%s*%-*$")
  if not core and (text:find("separatorLine", 1, true) or text:find("\226\128\148", 1, true)) then
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    core = text:match("(Previous session.-%d%d:%d%d)") or text:match("(Previous session.-earlier)")
  end
  if not core then return nil end
  return (core:gsub(", ended ", " · "))
end
Core.Components.SeparatorText = SeparatorText

-- The separator's lines beside a line of a separate window (one of the game's
-- own text lines): the same lines as the chat's, fading in and out with it
local function DrawSeparatorLines(fontString, show)
  if not show then
    if fontString.glassLineLeft then
      fontString.glassLineLeft:Hide()
      fontString.glassLineRight:Hide()
    end
    return
  end

  if not fontString.glassLineLeft then
    for _, side in ipairs({ "Left", "Right" }) do
      local line = fontString:GetParent():CreateTexture(nil, "ARTWORK")
      line:SetColorTexture(1, 1, 1, 1)
      line:SetHeight(1)
      fontString["glassLine"..side] = line
    end
    -- The game fades its lines out by their opacity
    hooksecurefunc(fontString, "SetAlpha", function (_, alpha)
      if fontString.glassSeparator then
        fontString.glassLineLeft:SetAlpha(alpha)
        fontString.glassLineRight:SetAlpha(alpha)
      end
    end)
  end

  local gold = Colors.apache
  local half = fontString:GetStringWidth() / 2 + SEPARATOR_GAP
  local left, right = fontString.glassLineLeft, fontString.glassLineRight
  left:ClearAllPoints()
  left:SetPoint("LEFT", fontString, "LEFT")
  left:SetPoint("RIGHT", fontString, "CENTER", -half, 0)
  left:SetGradient("HORIZONTAL",
    CreateColor(gold.r, gold.g, gold.b, 0), CreateColor(gold.r, gold.g, gold.b, SEPARATOR_ALPHA))
  right:ClearAllPoints()
  right:SetPoint("LEFT", fontString, "CENTER", half, 0)
  right:SetPoint("RIGHT", fontString, "RIGHT")
  right:SetGradient("HORIZONTAL",
    CreateColor(gold.r, gold.g, gold.b, SEPARATOR_ALPHA), CreateColor(gold.r, gold.g, gold.b, 0))
  for _, line in ipairs({ left, right }) do
    line:SetAlpha(fontString:GetAlpha())
    line:Show()
  end
end
Core.Components.DrawSeparatorLines = DrawSeparatorLines

function MessageLineMixin:LayoutSeparator()
  local gold = Colors.apache
  local half = self.text:GetStringWidth() / 2 + SEPARATOR_GAP
  for _, side in ipairs({ "Left", "Right" }) do
    local key = "separator"..side
    if not self[key] then
      self[key] = self:CreateTexture(nil, "ARTWORK")
      self[key]:SetColorTexture(1, 1, 1, 1)
      self[key]:SetHeight(1)
    end
  end
  self.separatorLeft:ClearAllPoints()
  self.separatorLeft:SetPoint("LEFT", Constants.TEXT_XPADDING, 0)
  self.separatorLeft:SetPoint("RIGHT", self, "CENTER", -half, 0)
  self.separatorLeft:SetGradient("HORIZONTAL",
    CreateColor(gold.r, gold.g, gold.b, 0), CreateColor(gold.r, gold.g, gold.b, SEPARATOR_ALPHA))
  self.separatorRight:ClearAllPoints()
  self.separatorRight:SetPoint("LEFT", self, "CENTER", half, 0)
  self.separatorRight:SetPoint("RIGHT", -Constants.TEXT_XPADDING, 0)
  self.separatorRight:SetGradient("HORIZONTAL",
    CreateColor(gold.r, gold.g, gold.b, SEPARATOR_ALPHA), CreateColor(gold.r, gold.g, gold.b, 0))
end

---
-- Shows this line as a normal message or as the separator
function MessageLineMixin:SetSeparator(isSeparator)
  self.isSeparator = isSeparator
  self.text:SetJustifyH(isSeparator and "CENTER" or "LEFT")
  for _, texture in ipairs({ self.leftBg, self.centerBg, self.rightBg }) do
    if texture then texture:SetShown(not isSeparator) end
  end
  if isSeparator then
    local gold = Colors.apache
    self.text:SetTextColor(gold.r, gold.g, gold.b, 0.8)
    self:LayoutSeparator()
  end
  if self.separatorLeft then
    self.separatorLeft:SetShown(isSeparator)
    self.separatorRight:SetShown(isSeparator)
  end
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
