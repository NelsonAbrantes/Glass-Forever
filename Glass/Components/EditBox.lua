local Core, Constants = unpack(select(2, ...))

local AceHook = Core.Libs.AceHook

local Colors = Constants.COLORS

local UPDATE_CONFIG = Constants.EVENTS.UPDATE_CONFIG

-- luacheck: push ignore 113
local CreateColor = CreateColor
local Mixin = Mixin
-- luacheck: pop

local ASSETS = "Interface\\Addons\\Glass\\Glass\\Assets\\"
local SLICE_MARGIN = 8 -- size of the rounded corners in the shape files

-- Sets a rounded shape that keeps its corners however wide the box is
local function SetShape(texture, file)
  texture:SetTexture(ASSETS..file)
  if texture.SetTextureSliceMargins then
    texture:SetTextureSliceMargins(SLICE_MARGIN, SLICE_MARGIN, SLICE_MARGIN, SLICE_MARGIN)
    if texture.SetTextureSliceMode and _G.Enum and _G.Enum.UITextureSliceMode then
      texture:SetTextureSliceMode(_G.Enum.UITextureSliceMode.Stretched)
    end
  end
end

local EditBoxMixin = {}

local LINE_ALPHA = 0.8 -- the Minimal style's line under the box

---
-- The look of the box, from the Edit box options:
-- - minimal: like the messages, a dark background that fades out at the ends,
--   with a thin line under it in the color of the chat you're typing in
-- - solid: a plain dark box
-- - framed: rounded corners and a border in the chat's color
function EditBoxMixin:UpdateStyle()
  local style = Core.db.profile.editBoxStyle
  local opacity = Core.db.profile.editBoxBackgroundOpacity
  local minimal = style ~= "solid" and style ~= "framed"

  self.glassBg:SetShown(style == "solid")
  self.frameBg:SetShown(style == "framed")
  self.frameBorder:SetShown(style == "framed")

  -- Same fade as the message lines
  self:SetGradientBackground(50, 250, Colors.codGray, opacity)
  for _, texture in ipairs({ self.leftBg, self.centerBg, self.rightBg, self.lineLeft, self.lineRight }) do
    texture:SetShown(minimal)
  end

  self.frameBg:SetVertexColor(Colors.codGray.r, Colors.codGray.g, Colors.codGray.b, opacity)
  self:UpdateBorderColor()
end

function EditBoxMixin:UpdateBorderColor()
  local r, g, b = self.header:GetTextColor()
  if not r or (issecretvalue and issecretvalue(r)) then
    r, g, b = Colors.apache.r, Colors.apache.g, Colors.apache.b
  end
  self.frameBorder:SetVertexColor(r, g, b, 0.9)

  -- The line fades in from the left and out to the right
  self.lineLeft:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, LINE_ALPHA))
  self.lineRight:SetGradient("HORIZONTAL", CreateColor(r, g, b, LINE_ALPHA), CreateColor(r, g, b, 0))
end


function EditBoxMixin:Init(parent)
  -- Hide default styling. The game shows these again in several ways (Show,
  -- SetShown, SetAlpha), so they're kept fully transparent as well.
  for _, part in ipairs({ "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }) do
    local texture = _G[self:GetName()..part]
    if texture then
      texture:Hide()
      texture:SetAlpha(0)
      self:SecureHook(texture, "Show", function () texture:Hide() end)
      self:SecureHook(texture, "SetShown", function (_, shown)
        if shown then texture:Hide() end
      end)
      self:SecureHook(texture, "SetAlpha", function (_, alpha)
        if alpha ~= 0 then texture:SetAlpha(0) end
      end)
    end
  end

  -- New styling
  self:ClearAllPoints()

  self:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 8, Core.db.profile.editBoxAnchor.yOfs)

  if Core.db.profile.editBoxAnchor.position == "ABOVE" then
    self:ClearAllPoints()
    self:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", 8, Core.db.profile.editBoxAnchor.yOfs)
  end

  self:SetFontObject("GlassEditBoxFont")
  self:SetWidth(Core.db.profile.frameWidth - 8 * 2)
  self.header:SetFontObject("GlassEditBoxFont")
  self.header:SetPoint("LEFT", 8, 0)

  local bg = self:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(
    Colors.codGray.r, Colors.codGray.g, Colors.codGray.b, Core.db.profile.editBoxBackgroundOpacity
  )
  bg:SetAllPoints()
  self.glassBg = bg

  -- "Framed" style: rounded background and a border in the color of the
  -- chat type you're typing in (say, party, whisper...)
  self.frameBg = self:CreateTexture(nil, "BACKGROUND")
  self.frameBg:SetAllPoints()
  SetShape(self.frameBg, "tabBackground")
  self.frameBorder = self:CreateTexture(nil, "BORDER")
  self.frameBorder:SetAllPoints()
  SetShape(self.frameBorder, "tabBorder")

  -- "Minimal" style line under the box, in two halves so it fades at both ends
  self.lineLeft = self:CreateTexture(nil, "BORDER")
  self.lineLeft:SetColorTexture(1, 1, 1, 1)
  self.lineLeft:SetHeight(1)
  self.lineLeft:SetPoint("BOTTOMLEFT")
  self.lineLeft:SetPoint("BOTTOMRIGHT", self, "BOTTOM")
  self.lineRight = self:CreateTexture(nil, "BORDER")
  self.lineRight:SetColorTexture(1, 1, 1, 1)
  self.lineRight:SetHeight(1)
  self.lineRight:SetPoint("BOTTOMLEFT", self, "BOTTOM")
  self.lineRight:SetPoint("BOTTOMRIGHT")

  -- The game colors the header ("Say:", "To Name:"...) by chat type
  self:SecureHook(self.header, "SetTextColor", function ()
    self:UpdateBorderColor()
  end)
  self:UpdateStyle()

  local Ypadding = self.header:GetLineHeight() * 0.66
  self:SetHeight(self.header:GetLineHeight() + Ypadding * 2)

  self:RawHook(self, "SetTextInsets", function ()
    Ypadding = self.header:GetLineHeight() * 0.66
    self.hooks[self].SetTextInsets(
      self,
      self.header:GetStringWidth() + 8,
      8, Ypadding, Ypadding
    )
  end, true)

  self:SetTextInsets()

  -- Animations
  -- Intro animations
  local introAg = self:CreateAnimationGroup()
  local fadeIn = introAg:CreateAnimation("Alpha")
  fadeIn:SetFromAlpha(0)
  fadeIn:SetToAlpha(1)
  fadeIn:SetDuration(0.2)
  fadeIn:SetSmoothing("OUT")

  -- Outro animations
  local outroAg = self:CreateAnimationGroup()
  local fadeOut = outroAg:CreateAnimation("Alpha")
  fadeOut:SetFromAlpha(1)
  fadeOut:SetToAlpha(0)
  fadeOut:SetDuration(0.05)

  -- Workaround for editbox being open on login
  self.glassInitialized = false

  self:SetScript("OnShow", function ()
    if self.glassInitialized then
      introAg:Play()
    else
      self.glassInitialized = true
    end
  end)

  outroAg:SetScript("OnFinished", function ()
    if not introAg:IsPlaying() then
      self.hooks[self].Hide(self)
    end
  end)

  self:RawHook(self, "Hide", function ()
    outroAg:Play()
  end, true)

  Core:Subscribe(UPDATE_CONFIG, function (key)
    if key == "font" or key == "editBoxFontSize" then
      Ypadding = self.header:GetLineHeight() * 0.66
      self:SetHeight(self.header:GetLineHeight() + Ypadding * 2)
      self:SetTextInsets()
    end

    if key == "frameWidth" then
      self:SetWidth(Core.db.profile.frameWidth - 8 * 2)
    end

    if key == "editBoxBackgroundOpacity" then
      bg:SetColorTexture(
        Colors.codGray.r, Colors.codGray.g, Colors.codGray.b, Core.db.profile.editBoxBackgroundOpacity
      )
      self:UpdateStyle()
    end

    if key == "editBoxStyle" then
      self:UpdateStyle()
    end

    if key == "editBoxAnchor" then
      if Core.db.profile.editBoxAnchor.position == "ABOVE" then
        self:ClearAllPoints()
        self:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", 8, Core.db.profile.editBoxAnchor.yOfs)
      else
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 8, Core.db.profile.editBoxAnchor.yOfs)
      end
    end
  end)
end

Core.Components.CreateEditBox = function (parent)
  local GradientBackgroundMixin = Core.Components.GradientBackgroundMixin
  local object = Mixin(_G.ChatFrame1EditBox, GradientBackgroundMixin, EditBoxMixin)
  AceHook:Embed(object)
  GradientBackgroundMixin.Init(object)
  object:Init(parent)
  return object
end
