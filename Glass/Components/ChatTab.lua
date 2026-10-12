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

        if key == "tabStyle" or key == "tabAccent" or key == "tabTextColor" or key == "font"
          or key == "tabLineAnimation" then
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
local SelectedBox = {} -- the sliding selected look of Framed, Solid, Pill and Glossy (below)
local fadingTabs = {} -- tabs whose look is fading now (see FadeLayer)

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
  self.bottom = Utils.TabBarAtBottom()
  self:AnchorGlow()
end

-- The glow goes into the tab: up from the line when it's under the names
-- (Underline's bar, or Minimal with the tab bar under the messages), down
-- from it otherwise (the image flipped for up)
function SelectedLine:AnchorGlow()
  local up = self.mode == "bar" or self.bottom
  if up == self.glowUp then return end
  self.glowUp = up
  local glow = self.glow
  glow:ClearAllPoints()
  if up then
    glow:SetPoint("BOTTOMLEFT", self.frame, "TOPLEFT", -LINE_GLOW_SPREAD, 0)
    glow:SetPoint("BOTTOMRIGHT", self.frame, "TOPRIGHT", LINE_GLOW_SPREAD, 0)
    glow:SetTexCoord(0, 1, 1, 0)
  else
    glow:SetPoint("TOPLEFT", self.frame, "BOTTOMLEFT", -LINE_GLOW_SPREAD, 0)
    glow:SetPoint("TOPRIGHT", self.frame, "BOTTOMRIGHT", LINE_GLOW_SPREAD, 0)
    glow:SetTexCoord(0, 1, 0, 1)
  end
end

-- "line" (Minimal): on the bar's edge facing the messages, fading out to the
-- ends, with a glow into the tab. "bar" (Underline): a thicker bar under the
-- name, only softened at its ends, with a glow rising from it that lights the
-- name from below.
local BAR_HEIGHT = 3
local BAR_EDGE_ALPHA = 0.25 -- the bar's ends (the line's fade out completely)
local BAR_GLOW_ALPHA = 0.45

function SelectedLine:SetMode(mode)
  if mode == self.mode then return end
  self.mode = mode
  self:AnchorGlow()
  self.color = nil -- colored again for this mode
  self.dirty = true
end

function SelectedLine:Color(color)
  if self.color == color then return end
  self.color = color
  local r, g, b = color[1], color[2], color[3]
  local bar = self.mode == "bar"
  local strong = CreateColor(r, g, b, 1)
  local edge = CreateColor(r, g, b, bar and BAR_EDGE_ALPHA or 0)
  self.left:SetGradient("HORIZONTAL", edge, strong)
  self.right:SetGradient("HORIZONTAL", strong, edge)
  self.glow:SetVertexColor(r, g, b, bar and BAR_GLOW_ALPHA or LINE_GLOW_ALPHA)
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

  local bar = self.mode == "bar"
  local targetX = tabLeft - dockLeft + tab:GetWidth() / 2
  local targetW = bar and (tab:GetWidth() - 2 * math.max(Utils.TabPadding() - 3, 0))
    or tab:GetWidth() * LINE_WIDTH_RATIO
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

  -- The line: the same thickness in real pixels whatever the UI scale. The
  -- bar: Underline's own bar height.
  local height = self.height or 1
  if bar then
    height = BAR_HEIGHT
  else
    local _, screenHeight = GetPhysicalScreenSize()
    local scale = tab:GetEffectiveScale()
    if screenHeight and screenHeight > 0 and scale and scale > 0 then
      height = LINE_THICKNESS_PIXELS * (768 / screenHeight) / scale
    end
  end

  if self.dirty or x ~= self.x or w ~= self.w or height ~= self.height then
    self.dirty = false
    self.x, self.w, self.height = x, w, height
    frame:SetSize(math.max(1, w), height)
    -- On the edge of the tab bar itself, not of the tab: the game places the
    -- scrolling tabs (Guild, Party, whispers) 1px lower than General and
    -- Combat Log, and the line moved down with them
    frame:ClearAllPoints()
    if bar then
      -- Under the names, where Underline draws its bar
      frame:SetPoint("BOTTOM", dock, "BOTTOMLEFT", x, 1)
    elseif self.bottom then
      frame:SetPoint("BOTTOM", dock, "BOTTOMLEFT", x, 0)
    else
      frame:SetPoint("TOP", dock, "TOPLEFT", x, 0)
    end
  end
  if not frame:IsShown() then frame:Show() end
end

-- True while the line slides or a tab's look fades (UIManager then updates
-- them every frame)
Core.Components.TabLineMoving = function ()
  return SelectedLine.movedAt ~= nil or SelectedBox.movedAt ~= nil or next(fadingTabs) ~= nil
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
----
-- Slide (Framed, Solid, Pill, Glossy): the selected look (background, shine
-- and border) is one piece for the whole tab bar, under the tabs, that
-- slides from the old tab to the new one, stretching or shrinking to its
-- size. The selected tab itself then draws no background of its own, so the
-- piece shows through. On its way it passes under the tabs in between, which
-- dim it a little with their own backgrounds.

-- Framed, Solid, Pill and Glossy slide with "Slide"; Minimal and Underline
-- have their own line, Classic is the game's art
local BOX_MOVE_TIME = 0.3  -- seconds the selected look takes to slide
local BOX_GROW_TIME = 0.28 -- seconds it takes to open (Grow)
local BOX_GROW_FROM = 0.3  -- size it opens from, as a fraction of the tab
local BOX_FADE_PART = 0.45 -- part of the Grow time the new look fades in over
local BOX_HANDOFF = 0.08   -- seconds the tab just left waits before its own look comes back (Grow)

-- Framed, Solid, Pill and Glossy animate with "Slide" (the look travels
-- from tab to tab) and "Grow" (it opens from the middle of the new tab)
local function BoxSlides(style)
  local animation = Core.db.profile.tabLineAnimation
  return style.shape ~= nil and not style.classic and (animation == "slide" or animation == "grow")
end

-- A piece showing the selected look: a frame with a background, shine and
-- border. There are two: the one on the selected tab, and with Grow a ghost
-- that shrinks and fades out on the tab just left.
local function NewPiece(dock)
  -- At the tab bar's own level: drawn over its background, under the tabs
  local frame = CreateFrame("Frame", nil, dock)
  frame:SetFrameLevel(dock:GetFrameLevel())
  frame:SetSize(1, 1)
  frame:Hide()
  frame.layers = {
    frame:CreateTexture(nil, "BACKGROUND", nil, -8), -- background
    frame:CreateTexture(nil, "BACKGROUND", nil, -7), -- shine
    frame:CreateTexture(nil, "BACKGROUND", nil, -6), -- border
  }
  for _, texture in ipairs(frame.layers) do
    texture:SetAllPoints()
    if texture.SetSnapToPixelGrid then
      texture:SetSnapToPixelGrid(false)
      texture:SetTexelSnappingBias(0)
    end
  end
  frame.opacity = 1
  return frame
end

function SelectedBox:Create()
  if self.frame then return true end
  local dock = _G.GeneralDockManager
  if not dock then return false end
  self.frame = NewPiece(dock)
  self.ghost = NewPiece(dock)
  return true
end

-- How visible a piece is, through its colors' alpha (in this game version a
-- texture's own alpha replaces that)
local function SetPieceOpacity(frame, opacity, force)
  if frame.opacity == opacity and not force then return end
  frame.opacity = opacity
  for i, texture in ipairs(frame.layers) do
    local c = frame.colors and frame.colors[i]
    if c then texture:SetVertexColor(c[1], c[2], c[3], c[4] * opacity) end
  end
end

-- The style's selected look, drawn again only when the style or accent changes
function SelectedBox:Configure(style)
  local name, accent = Core.db.profile.tabStyle, Core.db.profile.tabAccent
  if name == self.styleName and accent == self.accent then return end
  self.styleName, self.accent = name, accent
  local specs = {
    { style.shape, style.bg and style.bg.selected },
    { style.shine, style.shineColor and style.shineColor.selected },
    { style.border, style.borderColor and style.borderColor.selected },
  }
  for _, frame in ipairs({ self.frame, self.ghost }) do
    frame.colors = {}
    for i, spec in ipairs(specs) do
      local texture, file, color = frame.layers[i], spec[1], spec[2]
      if file and color then
        SetShape(texture, file, style.margin)
        frame.colors[i] = { Resolve(color, style) }
        texture:Show()
      else
        texture:Hide()
      end
    end
    SetPieceOpacity(frame, frame.opacity, true)
  end
end

function SelectedBox:Hide()
  if self.frame and self.frame:IsShown() then self.frame:Hide() end
  if self.ghost and self.ghost:IsShown() then self.ghost:Hide() end
  self.tab = nil
  self.movedAt = nil
end

-- Puts the selected look on `tab`, sliding there from the tab it was on
function SelectedBox:Follow(tab)
  local frame = self.frame
  local dock = frame:GetParent()
  local dockLeft, dockBottom = dock:GetLeft(), dock:GetBottom()
  local tabLeft, tabBottom = tab:GetLeft(), tab:GetBottom()
  if not dockLeft or not tabLeft or not dockBottom or not tabBottom then return end

  -- Where the tab's own background would be (2px in at the sides, 1px at
  -- the top and bottom)
  local targetH = math.max(1, tab:GetHeight() - 2)
  local targetX = tabLeft - dockLeft + tab:GetWidth() / 2
  local targetY = tabBottom - dockBottom + 1 + targetH / 2 -- its middle
  local targetW = math.max(1, tab:GetWidth() - 4)
  local now = GetTime()

  -- Another tab: Slide travels from where it is, Grow opens from the middle
  -- of the new tab. The first time it's just there.
  if tab ~= self.tab then
    local grow = Core.db.profile.tabLineAnimation == "grow"
    if self.tab and frame:IsShown() and self.x then
      self.growing = grow
      if grow then
        -- The ghost takes over where the look was, to shrink away there
        local ghost = self.ghost
        ghost.x, ghost.y, ghost.w, ghost.h = self.x, self.y, self.w, self.h
        ghost:SetSize(math.max(1, ghost.w), math.max(1, ghost.h))
        ghost:ClearAllPoints()
        ghost:SetPoint("CENTER", dock, "BOTTOMLEFT", ghost.x, ghost.y)
        SetPieceOpacity(ghost, 1)
        ghost:Show()
        self.fromX, self.fromY = targetX, targetY
        self.fromW, self.fromH = targetW * BOX_GROW_FROM, targetH * BOX_GROW_FROM
      else
        self.ghost:Hide()
        self.fromX, self.fromY, self.fromW, self.fromH = self.x, self.y, self.w, self.h
      end
      self.movedAt = now
    else
      self.movedAt = nil
    end
    self.tab = tab
  end

  local x, y, w, h = targetX, targetY, targetW, targetH
  local opacity = 1
  if self.movedAt then
    local duration = self.growing and BOX_GROW_TIME or BOX_MOVE_TIME
    local k = (now - self.movedAt) / duration
    if k < 1 then
      local ease
      if self.growing then
        -- Opens with a small pop past its size, then settles, fading in
        -- over its first part
        local back = k - 1
        ease = 1 + 2.4 * back * back * back + 1.4 * back * back
        opacity = math.min(1, k / BOX_FADE_PART)
        opacity = opacity * opacity * (3 - 2 * opacity)
        -- Meanwhile the ghost on the old tab shrinks to its middle and fades
        local ghost = self.ghost
        local out = k * k
        local scale = 1 - (1 - BOX_GROW_FROM) * out
        ghost:SetSize(math.max(1, ghost.w * scale), math.max(1, ghost.h * scale))
        -- Fades over the whole time, while the tab's own look comes back
        -- under it: no moment with the tab empty (that looked like a flicker)
        SetPieceOpacity(ghost, 1 - k)
      else
        -- Speeds up softly, glides, slows down softly (a fast start looked
        -- like a jump)
        ease = k < 0.5 and 4 * k * k * k or 1 - (-2 * k + 2) ^ 3 / 2
      end
      x = self.fromX + (targetX - self.fromX) * ease
      y = self.fromY + (targetY - self.fromY) * ease
      w = self.fromW + (targetW - self.fromW) * ease
      h = self.fromH + (targetH - self.fromH) * ease
    else
      self.movedAt = nil
      self.ghost:Hide()
    end
  end
  SetPieceOpacity(frame, opacity)

  if x ~= self.x or y ~= self.y or w ~= self.w or h ~= self.h then
    self.x, self.y, self.w, self.h = x, y, w, h
    frame:SetSize(math.max(1, w), math.max(1, h))
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", dock, "BOTTOMLEFT", x, y)
  end
  if not frame:IsShown() then frame:Show() end
end

----
-- Smooth changes between a tab's states (Framed, Solid, Pill, Glossy): the
-- background, shine and border fade from their old color to the new one, so
-- the selected look passes from tab to tab and the hover look comes and goes
-- softly. Colors only, through the vertex color (in this game version a
-- texture's own alpha replaces it).

local FADE_TIME = 0.2

function ChatTabMixin:FadeLayer(texture, r, g, b, a)
  local current = texture.glassColor
  -- Already fading to this color: a redraw meanwhile leaves the fade going
  local to = texture.glassTo
  if texture.glassFrom and to and to[1] == r and to[2] == g and to[3] == b and to[4] == a then
    return
  end
  if not self.styleFades or not current then
    texture:SetVertexColor(r, g, b, a)
    texture.glassColor = { r, g, b, a }
    texture.glassFrom = nil
    return
  end
  -- From what it shows now (or invisible, if it was hidden) to the new color
  local from = texture.glassFrom or {}
  from[1], from[2], from[3] = current[1], current[2], current[3]
  from[4] = texture:IsShown() and current[4] or 0
  texture.glassFrom = from
  local target = to or {}
  target[1], target[2], target[3], target[4] = r, g, b, a
  texture.glassTo = target
  -- (later on the tab just left, while the Grow ghost shrinks away there)
  self.fadeStart = GetTime() + (self.handOffDelay or 0)
  fadingTabs[self] = true
end

function ChatTabMixin:StepStyleFade(now)
  if not self.fadeStart then return end
  local k = (now - self.fadeStart) / FADE_TIME
  local done = k >= 1
  if done then k = 1 end
  if k < 0 then k = 0 end -- still waiting (hand-off to the Grow ghost)
  local ease = k * k * (3 - 2 * k)
  for _, texture in ipairs({ self.styleBg, self.styleShine, self.styleBorder }) do
    local from, to = texture.glassFrom, texture.glassTo
    if from and to then
      local c = texture.glassColor
      for i = 1, 4 do c[i] = from[i] + (to[i] - from[i]) * ease end
      texture:SetVertexColor(c[1], c[2], c[3], c[4])
      if done then texture.glassFrom = nil end
    end
  end
  if done then
    self.fadeStart = nil
    fadingTabs[self] = nil
  end
end

-- A layer's color; invisible on the selected tab while the sliding piece
-- draws its look (SelectedBox)
local function LayerColor(spec, style, hidden)
  local r, g, b, a = Resolve(spec, style)
  return r, g, b, hidden and 0 or a
end

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
  -- Only a change of state (selected, hover, normal) fades; a new style or
  -- accent color shows at once. (Not tied to the redraw flag: the game lays
  -- the tabs out again when one is clicked, which asks for a redraw right as
  -- the state changes, and that skipped the fade.)
  self.styleFades = state ~= self.styleState and styleName == self.styleName
    and accent == self.styleAccent and Core.db.profile.tabLineAnimation ~= "off"
  -- With the sliding or growing piece (SelectedBox), the tab's own look
  -- hands over to it: gone at once on the newly selected tab, so the piece
  -- shows from the start; back only after the piece left (Grow: its ghost
  -- shrinks away there first) on the tab just left. Otherwise the tab's own
  -- dark background covered the piece.
  local leaving = self.styleState == "selected" and state ~= "selected"
  if state == "selected" and BoxSlides(CurrentStyle()) then
    self.styleFades = false
  end
  self.handOffDelay = (self.styleFades and leaving and BoxSlides(CurrentStyle())
    and Core.db.profile.tabLineAnimation == "grow") and BOX_HANDOFF or nil
  self.styleKey = true
  self.styleName, self.styleState, self.styleAccent = styleName, state, accent
  self.styleSelected = isSelected
  local style = CurrentStyle()
  -- The selected look slides as one piece (SelectedBox): this tab shows none
  local hideSelected = state == "selected" and BoxSlides(style)

  self:ShowClassic(style.classic == true)
  if style.classic then
    self:TintClassic()
  end

  -- Background
  local bg = style.bg and style.bg[state]
  if style.shape and bg then
    SetShape(self.styleBg, style.shape, style.margin)
    self:FadeLayer(self.styleBg, LayerColor(bg, style, hideSelected))
    self.styleBg:Show()
  else
    self.styleBg:Hide()
  end

  -- Shine on the top half (Glossy)
  local shine = style.shineColor and style.shineColor[state]
  if style.shine and shine then
    SetShape(self.styleShine, style.shine, style.margin)
    self:FadeLayer(self.styleShine, LayerColor(shine, style, hideSelected))
    self.styleShine:Show()
  else
    self.styleShine:Hide()
  end

  -- Border
  local border = style.borderColor and style.borderColor[state]
  if style.border and border then
    SetShape(self.styleBorder, style.border, style.margin)
    self:FadeLayer(self.styleBorder, LayerColor(border, style, hideSelected))
    self.styleBorder:Show()
  else
    self.styleBorder:Hide()
  end

  -- Bar under the name (Underline). The selected tab's bar is drawn by the
  -- shared SelectedLine when it's animated, so it can slide between tabs.
  local bar = style.bar and style.bar[state]
  if bar and state == "selected" and Core.db.profile.tabLineAnimation ~= "off" then
    bar = nil
  end
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

  -- Line above the selected tab (Minimal) or bar under it (Underline), in
  -- the accent color
  if style.line or style.bar then
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
  self:StepStyleFade(GetTime())
  if not isSelected then return end

  -- The shared line: Minimal's line always, Underline's bar when animated.
  -- The other styles draw the selected tab themselves.
  local style = CurrentStyle()
  local mode = style.line and "line"
    or (style.bar and Core.db.profile.tabLineAnimation ~= "off" and "bar")
  if mode and self:IsVisible() then
    if SelectedLine:Create() then
      SelectedLine:SetMode(mode)
      SelectedLine:Color(self.lineColor)
      SelectedLine:Follow(self)
    end
  else
    SelectedLine:Hide()
  end

  -- The box styles' sliding selected look (Slide)
  if BoxSlides(style) and self:IsVisible() then
    if SelectedBox:Create() then
      SelectedBox:Configure(style)
      SelectedBox:Follow(self)
    end
  else
    SelectedBox:Hide()
  end
end

Core.Components.CreateChatTab = function (slidingMessageFrame)
  local frame = _G[slidingMessageFrame.chatFrame:GetName().."Tab"]
  local object = Mixin(frame, ChatTabMixin)
  AceHook:Embed(object)
  object:Init(slidingMessageFrame)
  return object
end