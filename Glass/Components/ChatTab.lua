local Core, Constants, Utils = unpack(select(2, ...))

local AceHook = Core.Libs.AceHook

local UnlockMover = Constants.ACTIONS.UnlockMover

local Colors = Constants.COLORS

local UPDATE_CONFIG = Constants.EVENTS.UPDATE_CONFIG

-- luacheck: push ignore 113
local DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME
local ChatTypeInfo = ChatTypeInfo
local FCF_StopAlertFlash = FCF_StopAlertFlash
local CreateColor = CreateColor
local CreateFrame = CreateFrame
local GetPhysicalScreenSize = GetPhysicalScreenSize
local GetTime = GetTime
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

-- The soft glow from the selected line into the tab (Minimal style)
local LINE_GLOW_HEIGHT = 12
local LINE_GLOW_SPREAD = 6   -- how much wider than the line, on each side
local LINE_GLOW_ALPHA = 0.35

-- The new message glow is bright: pale chat colors (party is a very light
-- blue) turned white in it, so it gets a stronger version of the color.
-- White stays white. Blues (equal red and green, like party) looked purple
-- that strong, so they lean towards sky blue.
local GLOW_SATURATION = 2.5
local SKY_BLUE = 0.5 -- how far a blue's green goes up towards its blue
local function GlowColor(color)
  local r, g, b = color.r, color.g, color.b
  local top = math.max(r, g, b)
  local function push(c) return math.max(0, top - (top - c) * GLOW_SATURATION) end
  r, g, b = push(r), push(g), push(b)
  if b == top and b > g and math.abs(r - g) < 0.1 then
    g = g + (b - g) * SKY_BLUE
  end
  return r, g, b
end

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
      -- Temporary chat frames (whispers) retain their color
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
        Adjust(function () self.glow:SetVertexColor(GlowColor(color)) end)
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
        Adjust(function () self.glow:SetVertexColor(GlowColor(color)) end)
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

  -- The line of the selected tab is one for the whole tab bar (see
  -- SelectedLine below), so it can slide from tab to tab. Each tab only
  -- keeps its color for it.
  self.lineColor = self.lineColor or { Colors.apache.r, Colors.apache.g, Colors.apache.b }

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
        if key == "frameWidth" or key == "font" or key == "messageFontSize"
          or key == "tabFont" or key == "tabFontSize" or key == "tabBarHeight" or key == "tabPadding"
          or key == "tabBarPosition" then
          -- Fit the tab to its text, the bar height and the spacing
          self:UpdateLayout()
        end

        if key == "tabStyle" or key == "tabAccent" or key == "tabTextColor" or key == "font" then
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
  -- The name's position is set in the SetWidth hook (it moves when the tab is
  -- shrunk to fit the bar)
  self.textLeft = nil
  self:SetWidth(self:FitText() + padding * 2)
  self.styleKey = nil -- redraw the style (the Underline bar depends on the spacing)
  self:PlaceSelectedLine()
end

----
-- The selected line (Minimal style): one for the whole tab bar, on the side
-- facing the messages. Strongest in the middle and fading out to the ends,
-- with a soft glow into the tab. When another tab is selected it slides
-- there, stretching or shrinking to the new tab's size; the first time it
-- opens from the middle. It belongs to the tab bar, not to a tab, so it isn't
-- cut off where the scrolling tabs end.

local LINE_THICKNESS_PIXELS = 2 -- in real screen pixels
local LINE_WIDTH_RATIO = 0.75   -- fraction of the tab width (the ends fade out)
local LINE_MOVE_TIME = 0.25     -- seconds to slide to another tab (or open)

local SelectedLine = {}

function SelectedLine:Create()
  if self.frame then return true end
  local dock = _G.GeneralDockManager
  if not dock then return false end
  local frame = CreateFrame("Frame", nil, dock)
  frame:SetFrameLevel(dock:GetFrameLevel() + 20)
  frame:SetSize(1, 1)
  frame:Hide()
  self.frame = frame

  self.left = frame:CreateTexture(nil, "OVERLAY")
  self.left:SetPoint("TOPLEFT")
  self.left:SetPoint("BOTTOMRIGHT", frame, "BOTTOM")
  self.right = frame:CreateTexture(nil, "OVERLAY")
  self.right:SetPoint("TOPLEFT", frame, "TOP")
  self.right:SetPoint("BOTTOMRIGHT")
  -- A soft half-ellipse of light (an image, so it's smooth at any size)
  self.glow = frame:CreateTexture(nil, "ARTWORK")
  self.glow:SetTexture(ASSETS.."tabGlow")
  self.glow:SetBlendMode("ADD")
  self.glow:SetHeight(LINE_GLOW_HEIGHT)
  for _, texture in ipairs({ self.left, self.right }) do
    texture:SetColorTexture(1, 1, 1, 1)
  end
  for _, texture in ipairs({ self.left, self.right, self.glow }) do
    -- Not snapped to whole pixels: smooth edges and a smooth slide
    if texture.SetSnapToPixelGrid then
      texture:SetSnapToPixelGrid(false)
      texture:SetTexelSnappingBias(0)
    end
  end
  self:Place()
  return true
end

-- The glow goes into the tab: below the line, or above it when the tab bar
-- is under the messages (the image flipped)
function SelectedLine:Place()
  if not self.frame then return end
  -- Placed again on its next update, without forgetting where it is (the
  -- game lays the tabs out again when one is clicked: forgetting it made
  -- "Slide" always grow from the middle instead)
  self.dirty = true
  local bottom = Utils.TabBarAtBottom()
  if bottom == self.bottom then return end
  local glow = self.glow
  glow:ClearAllPoints()
  self.bottom = bottom
  if self.bottom then
    glow:SetPoint("BOTTOMLEFT", self.frame, "TOPLEFT", -LINE_GLOW_SPREAD, 0)
    glow:SetPoint("BOTTOMRIGHT", self.frame, "TOPRIGHT", LINE_GLOW_SPREAD, 0)
    glow:SetTexCoord(0, 1, 1, 0)
  else
    glow:SetPoint("TOPLEFT", self.frame, "BOTTOMLEFT", -LINE_GLOW_SPREAD, 0)
    glow:SetPoint("TOPRIGHT", self.frame, "BOTTOMRIGHT", LINE_GLOW_SPREAD, 0)
    glow:SetTexCoord(0, 1, 0, 1)
  end
end

function SelectedLine:Color(color)
  if self.color == color then return end
  self.color = color
  local r, g, b = color[1], color[2], color[3]
  local clear, strong = CreateColor(r, g, b, 0), CreateColor(r, g, b, 1)
  self.left:SetGradient("HORIZONTAL", clear, strong)
  self.right:SetGradient("HORIZONTAL", strong, clear)
  self.glow:SetVertexColor(r, g, b, LINE_GLOW_ALPHA)
end

function SelectedLine:Hide()
  if self.frame and self.frame:IsShown() then self.frame:Hide() end
  self.tab = nil
end

-- Puts the line on `tab`, sliding there if it was on another one. Called
-- every frame for the selected tab: only does work while something changes.
function SelectedLine:Follow(tab)
  if not self:Create() then return end
  local frame = self.frame
  local dock = frame:GetParent()
  local dockLeft, tabLeft = dock:GetLeft(), tab:GetLeft()
  if not dockLeft or not tabLeft then return end

  local targetX = tabLeft - dockLeft + tab:GetWidth() / 2
  local targetW = tab:GetWidth() * LINE_WIDTH_RATIO
  local now = GetTime()

  -- Another tab (Tabs options: Selected line animation)
  if tab ~= self.tab then
    local animation = Core.db.profile.tabLineAnimation or "slide"
    if animation == "off" then
      self.movedAt = nil
    elseif animation == "slide" and self.tab and frame:IsShown() and self.x then
      self.fromX, self.fromW = self.x, self.w -- slide from where it is
      self.movedAt = now
    else
      self.fromX, self.fromW = targetX, 0     -- grow from the middle
      self.movedAt = now
    end
    self.tab = tab
  end

  local x, w = targetX, targetW
  if self.movedAt then
    local k = (now - self.movedAt) / LINE_MOVE_TIME
    if k < 1 then
      local ease = 1 - (1 - k) ^ 3 -- fast start, soft landing
      x = self.fromX + (targetX - self.fromX) * ease
      w = self.fromW + (targetW - self.fromW) * ease
    else
      self.movedAt = nil
    end
  end

  -- The same thickness in real pixels whatever the UI scale
  local _, screenHeight = GetPhysicalScreenSize()
  local scale = tab:GetEffectiveScale()
  local height = self.height or 1
  if screenHeight and screenHeight > 0 and scale and scale > 0 then
    height = LINE_THICKNESS_PIXELS * (768 / screenHeight) / scale
  end

  if self.dirty or x ~= self.x or w ~= self.w or height ~= self.height then
    self.dirty = false
    self.x, self.w, self.height = x, w, height
    frame:SetSize(math.max(1, w), height)
    frame:ClearAllPoints()
    if self.bottom then
      frame:SetPoint("BOTTOM", dock, "BOTTOMLEFT", x, (tab:GetBottom() or 0) - (dock:GetBottom() or 0))
    else
      frame:SetPoint("TOP", dock, "TOPLEFT", x, (tab:GetTop() or 0) - (dock:GetTop() or 0))
    end
  end
  if not frame:IsShown() then frame:Show() end
end

-- True while the line slides or opens (UIManager then updates it every frame)
Core.Components.TabLineMoving = function ()
  return SelectedLine.movedAt ~= nil
end

-- The line's side follows the tab bar position
function ChatTabMixin:PlaceSelectedLine()
  SelectedLine:Place()
end

-- The selected line's color for this tab (the accent color)
function ChatTabMixin:ColorSelectedLine(r, g, b)
  local color = self.lineColor
  if not color or color[1] ~= r or color[2] ~= g or color[3] ~= b then
    self.lineColor = { r, g, b }
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

-- Tab name colors (Tabs options). "auto" isn't listed: it depends on the style.
local TEXT_COLORS = {
  gold = { Colors.apache.r, Colors.apache.g, Colors.apache.b },
  white = { 1, 1, 1 },
  silver = { 0.75, 0.75, 0.78 },
  dark = { 0.10, 0.07, 0.04 },
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
  glossy = {
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
  -- Whisper tabs keep the whisper color
  if self.chatFrame and self.chatFrame.isTemporary then return nil end

  local choice = Core.db.profile.tabTextColor
  local color = TEXT_COLORS[choice]
  if color then
    return color[1], color[2], color[3]
  end

  -- Auto: the Glass color, or dark on a filled selected tab (Solid). With an
  -- outline around the letters dark text gets lost, so it's white then.
  if CurrentStyle().darkTextSelected and self.styleSelected then
    if (Core.db.profile.fontFlags or ""):find("OUTLINE") then
      return 1, 1, 1
    end
    return TEXT_COLORS.dark[1], TEXT_COLORS.dark[2], TEXT_COLORS.dark[3]
  end
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

local CLASSIC_SELECTED = { "ActiveLeft", "ActiveMiddle", "ActiveRight" }

---
-- Classic style: the selected tab's art in the accent color. "Style default"
-- keeps the game's own colors. The art is made gray first, otherwise its own
-- colors mix with the accent.
function ChatTabMixin:TintClassic()
  local color = ACCENTS[Core.db.profile.tabAccent]
  for _, name in ipairs(CLASSIC_SELECTED) do
    local texture = self[name]
    if texture then
      texture:SetDesaturated(color ~= nil)
      if color then
        texture:SetVertexColor(color[1], color[2], color[3])
      else
        texture:SetVertexColor(1, 1, 1)
      end
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
  local state = isSelected and "selected" or (self.styleHover and "hover" or "normal")
  local accent = Core.db.profile.tabAccent
  -- Nothing changed (this runs many times a second): compared value by
  -- value, without building a text each time
  if self.styleKey and styleName == self.styleName and state == self.styleState
    and accent == self.styleAccent then
    return
  end
  self.styleKey = true
  self.styleName, self.styleState, self.styleAccent = styleName, state, accent
  self.styleSelected = isSelected
  local style = CurrentStyle()

  self:ShowClassic(style.classic == true)
  if style.classic then
    self:TintClassic()
  end

  -- Background
  local bg = style.bg and style.bg[state]
  if style.shape and bg then
    SetShape(self.styleBg, style.shape, style.margin)
    self.styleBg:SetVertexColor(Resolve(bg, style))
    self.styleBg:Show()
  else
    self.styleBg:Hide()
  end

  -- Shine on the top half (Glossy)
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
  if style.line then
    local r, g, b = Resolve(Accent(1), style)
    self:ColorSelectedLine(r, g, b)
  end

  -- Name color (Tabs options; "Auto" depends on the style)
  local r, g, b = self:DesiredTextColor()
  if r then self.Text:SetTextColor(r, g, b) end
end

function ChatTabMixin:UpdateSelected(selected)
  local isSelected = (self.chatFrame == selected)

  self:UpdateStyle(isSelected)
  if not isSelected then return end

  -- Only the Minimal style marks the selected tab with the line; the others
  -- draw it themselves
  if CurrentStyle().line == true and self:IsVisible() then
    if SelectedLine:Create() then
      SelectedLine:Color(self.lineColor)
      SelectedLine:Follow(self)
    end
  else
    SelectedLine:Hide()
  end
end

Core.Components.CreateChatTab = function (slidingMessageFrame)
  local frame = _G[slidingMessageFrame.chatFrame:GetName().."Tab"]
  local object = Mixin(frame, ChatTabMixin)
  AceHook:Embed(object)
  object:Init(slidingMessageFrame)
  return object
end