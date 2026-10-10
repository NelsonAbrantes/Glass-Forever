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

local ASSETS = "Interface\\AddOns\\Glass\\Glass\\Assets\\"

local ChatTabMixin = {}

function ChatTabMixin:Init(slidingMessageFrame)
  self.slidingMessageFrame = slidingMessageFrame
  self.chatFrame = slidingMessageFrame.chatFrame

  -- Remember the game's own tab textures (for the "Classic" tab style), then
  -- remove them: the other styles draw their own
  if self.classicTextures == nil then
    self.classicTextures = {}
    for _, texName in ipairs(tabTexs) do
      local texture = self[texName]
      self.classicTextures[texName] = { atlas = texture.GetAtlas and texture:GetAtlas(), file = texture:GetTexture() }
    end
  end
  for _, texName in ipairs(tabTexs) do
    self[texName]:SetTexture(nil)
  end
  self.classicShown = false

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
      local width = self:FitText() + Utils.TabPadding() * 2
      if math.abs(self:GetWidth() - width) > 0.5 then
        Adjust(function () self:SetWidth(width) end)
      end
    end)
  end

  if not self:IsHooked(self.Text, "SetTextColor") then
    self:SecureHook(self.Text, "SetTextColor", function ()
      -- Temporary chat frames retain their color (unless the style needs dark text)
      local r, g, b = self:DesiredTextColor()
      if r then
        Adjust(function () self.Text:SetTextColor(r, g, b) end)
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
    self.selectedLine:SetPoint("TOP", self, "TOP", 0, 0)
    self.selectedLine:SetSize(1, 1)
    self.selectedLine:Hide()
  end

  -- Layers used by the tab styles (Tabs options, see STYLES below): a
  -- background, a border and a bar under the name
  if self.styleBg == nil then
    self.styleBg = self:CreateTexture(nil, "BACKGROUND", nil, -8)
    self.styleShine = self:CreateTexture(nil, "BACKGROUND", nil, -7)
    self.styleBorder = self:CreateTexture(nil, "BACKGROUND", nil, -6)

    for _, texture in ipairs({ self.styleBg, self.styleShine, self.styleBorder }) do
      -- A small gap so neighbouring tabs don't touch
      texture:SetPoint("TOPLEFT", 2, -1)
      texture:SetPoint("BOTTOMRIGHT", -2, 1)
      texture:Hide()
    end

    self.styleBar = self:CreateTexture(nil, "OVERLAY")
    self.styleBar:SetColorTexture(1, 1, 1, 1)
    self.styleBar:SetPoint("BOTTOM", self, "BOTTOM", 0, 1)
    self.styleBar:Hide()

    local hookScript = getmetatable(self).__index.HookScript
    hookScript(self, "OnEnter", function () self.styleHover = true; self:UpdateStyle() end)
    hookScript(self, "OnLeave", function () self.styleHover = false; self:UpdateStyle() end)
  end
  self.styleKey = nil

  -- Listeners
  if self.subscriptions == nil then
    self.subscriptions = {
      Core:Subscribe(UPDATE_CONFIG, function (key)
        if key == "frameWidth" or key == "frameHeight" or key == "font" or key == "messageFontSize"
          or key == "tabFont" or key == "tabFontSize" or key == "tabBarHeight" or key == "tabPadding" then
          -- Fit the tab to its text, the bar height and the spacing
          self:UpdateLayout()
        end

        if key == "tabStyle" or key == "tabAccent" then
          self.styleKey = nil
          self:UpdateStyle()
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
  self.Text:ClearAllPoints()
  self.Text:SetPoint("LEFT", padding, 0)
  self:SetWidth(self:FitText() + padding * 2)
  self.styleKey = nil -- redraw the style (the Underline bar depends on the spacing)
end

---
-- Gives the tab name room for its full width and returns that width. The game
-- limits the width of tab names and cuts long ones ("Combat L..."); measuring
-- the cut text made the tab too narrow.
function ChatTabMixin:FitText()
  local width = self.Text.GetUnboundedStringWidth and self.Text:GetUnboundedStringWidth() or self:GetTextWidth()
  if issecretvalue and issecretvalue(width) then
    return self:GetTextWidth()
  end
  width = math.ceil(width) + 1
  if math.abs(self.Text:GetWidth() - width) > 0.5 then
    self.Text:SetWidth(width)
  end
  return width
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

-- Accent colors (Tabs options). "default" uses each style's own color.
local ACCENTS = {
  bronze = { 0.88, 0.62, 0.36 },
  gold = { 1.00, 0.82, 0.30 },
  cyan = { 0.30, 0.80, 0.95 },
  silver = { 0.82, 0.84, 0.88 },
  green = { 0.40, 0.90, 0.45 },
  purple = { 0.72, 0.50, 0.95 },
  red = { 0.95, 0.38, 0.32 },
}

-- A color that follows the accent color, with the given opacity
local function Accent(alpha, height)
  return { accent = true, a = alpha, h = height }
end

-- Tab styles. For each state (normal, hover, selected): bg and border colors
-- {r, g, b, a} drawn with the shape images, an optional bar under the name,
-- and the line above the selected tab (Minimal).
local STYLES = {
  minimal = { line = true, accentDefault = { Colors.apache.r, Colors.apache.g, Colors.apache.b } },
  framed = {
    shape = "tabBackground", border = "tabBorder", margin = 8,
    accentDefault = ACCENTS.bronze,
    bg = { normal = { 0, 0, 0, 0.5 }, hover = { 0.08, 0.08, 0.08, 0.65 }, selected = { 0.05, 0.05, 0.05, 0.75 } },
    borderColor = { normal = { 0.45, 0.33, 0.20, 0.7 }, hover = { 0.72, 0.49, 0.30, 0.9 }, selected = Accent(1) },
  },
  solid = {
    shape = "tabBackground", margin = 8, darkTextSelected = true,
    accentDefault = ACCENTS.bronze,
    bg = { normal = { 0.10, 0.10, 0.10, 0.7 }, hover = { 0.18, 0.18, 0.18, 0.8 }, selected = Accent(0.95) },
  },
  underline = {
    accentDefault = ACCENTS.bronze,
    bar = { hover = { 1, 1, 1, 0.35, h = 1 }, selected = Accent(1, 3) },
  },
  pill = {
    shape = "tabPill", border = "tabPillBorder", margin = 15,
    accentDefault = ACCENTS.bronze,
    bg = { normal = { 0, 0, 0, 0.45 }, hover = { 0.10, 0.10, 0.10, 0.6 }, selected = Accent(0.35) },
    borderColor = { normal = { 1, 1, 1, 0.12 }, hover = { 1, 1, 1, 0.3 }, selected = Accent(1) },
  },
  -- Raised, glossy buttons: a shaded background (lighter at the top), a shine
  -- on the top half and a dark border; the selected tab gets an orange border
  glass = {
    shape = "tabBevel", border = "tabBorder", shine = "tabShine", margin = 8,
    accentDefault = { 1.00, 0.55, 0.20 },
    bg = { normal = { 0.32, 0.24, 0.18, 0.9 }, hover = { 0.42, 0.32, 0.24, 0.92 }, selected = { 0.45, 0.22, 0.12, 0.95 } },
    borderColor = { normal = { 0, 0, 0, 0.85 }, hover = { 0.25, 0.18, 0.12, 0.9 }, selected = Accent(1) },
    shineColor = { normal = { 1, 1, 1, 0.6 }, hover = { 1, 1, 1, 0.7 }, selected = { 1, 1, 1, 0.8 } },
  },
  classic = { classic = true },
}

local function CurrentStyle()
  return STYLES[Core.db.profile.tabStyle] or STYLES.minimal
end

-- r, g, b, a of a color spec (or of the accent color)
local function Resolve(spec, style)
  if spec.accent then
    local c = ACCENTS[Core.db.profile.tabAccent] or style.accentDefault or ACCENTS.bronze
    return c[1], c[2], c[3], spec.a
  end
  return spec[1], spec[2], spec[3], spec[4]
end

local function SetShape(texture, file, margin)
  texture:SetTexture(ASSETS..file)
  -- Keep the rounded corners intact however wide the tab is
  if texture.SetTextureSliceMargins then
    texture:SetTextureSliceMargins(margin, margin, margin, margin)
    if texture.SetTextureSliceMode and _G.Enum and _G.Enum.UITextureSliceMode then
      texture:SetTextureSliceMode(_G.Enum.UITextureSliceMode.Stretched)
    end
  end
end

---
-- Text color of the tab name: dark on the filled selected tab (Solid), the
-- Glass color otherwise. nil keeps the game's color (whisper tabs).
function ChatTabMixin:DesiredTextColor()
  if CurrentStyle().darkTextSelected and self.styleSelected then
    return 0.10, 0.07, 0.04
  end
  if self.chatFrame and self.chatFrame.isTemporary then return nil end
  return Colors.apache.r, Colors.apache.g, Colors.apache.b
end

---
-- Shows the game's own tab textures (Classic style) or removes them
function ChatTabMixin:ShowClassic(show)
  if self.classicTextures == nil or show == self.classicShown then return end
  self.classicShown = show
  for name, info in pairs(self.classicTextures) do
    local texture = self[name]
    if not show then
      texture:SetTexture(nil)
    elseif info.atlas then
      texture:SetAtlas(info.atlas)
    elseif info.file then
      texture:SetTexture(info.file)
    end
  end
end

---
-- Draws the tab in the chosen style and colors it for its state (normal, under
-- the mouse, selected). Called every frame from UpdateSelected, so it only
-- changes things when something is different from last time.
function ChatTabMixin:UpdateStyle(isSelected)
  if self.styleBg == nil then return end
  if isSelected == nil then isSelected = self.styleSelected end

  local styleName = Core.db.profile.tabStyle or "minimal"
  local style = CurrentStyle()
  local state = isSelected and "selected" or (self.styleHover and "hover" or "normal")
  local key = styleName..":"..state..":"..tostring(Core.db.profile.tabAccent)
  if key == self.styleKey then return end
  self.styleKey = key
  self.styleSelected = isSelected

  self:ShowClassic(style.classic == true)

  -- Background
  local bg = style.bg and style.bg[state]
  if style.shape and bg then
    SetShape(self.styleBg, style.shape, style.margin)
    self.styleBg:SetVertexColor(Resolve(bg, style))
    self.styleBg:Show()
  else
    self.styleBg:Hide()
  end

  -- Shine on the top half (Glass)
  local shine = style.shineColor and style.shineColor[state]
  if style.shine and shine then
    SetShape(self.styleShine, style.shine, style.margin)
    self.styleShine:SetVertexColor(Resolve(shine, style))
    self.styleShine:Show()
  else
    self.styleShine:Hide()
  end

  -- Border
  local border = style.borderColor and style.borderColor[state]
  if style.border and border then
    SetShape(self.styleBorder, style.border, style.margin)
    self.styleBorder:SetVertexColor(Resolve(border, style))
    self.styleBorder:Show()
  else
    self.styleBorder:Hide()
  end

  -- Bar under the name (Underline)
  local bar = style.bar and style.bar[state]
  if bar then
    local inset = math.max(Utils.TabPadding() - 3, 0)
    self.styleBar:ClearAllPoints()
    self.styleBar:SetPoint("BOTTOMLEFT", inset, 1)
    self.styleBar:SetPoint("BOTTOMRIGHT", -inset, 1)
    self.styleBar:SetHeight(bar.h or 2)
    self.styleBar:SetColorTexture(Resolve(bar, style))
    self.styleBar:Show()
  else
    self.styleBar:Hide()
  end

  -- Line above the selected tab (Minimal), in the accent color
  if style.line and self.selectedLine then
    self.selectedLine:SetColorTexture(Resolve(Accent(1), style))
  end

  -- Name color (dark on a filled selected tab)
  local r, g, b = self:DesiredTextColor()
  if r then self.Text:SetTextColor(r, g, b) end
end

local LINE_THICKNESS_PIXELS = 2 -- thickness of the selected-tab line, in real screen pixels
local LINE_WIDTH_RATIO = 0.5    -- fraction of the tab width

function ChatTabMixin:UpdateSelected(selected)
  local line = self.selectedLine
  if line == nil then return end

  local isSelected = (self.chatFrame == selected)

  self:UpdateStyle(isSelected)

  -- Only the Minimal style marks the selected tab with the line; the others draw it
  local showLine = isSelected and CurrentStyle().line == true

  if showLine then
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

  if line:IsShown() ~= showLine then
    line:SetShown(showLine)
  end
end

Core.Components.CreateChatTab = function (slidingMessageFrame)
  local frame = _G[slidingMessageFrame.chatFrame:GetName().."Tab"]
  local object = Mixin(frame, ChatTabMixin)
  AceHook:Embed(object)
  object:Init(slidingMessageFrame)
  return object
end