local Core, Constants = unpack(select(2, ...))
local Fonts = Core:GetModule("Fonts")

local LSM = Core.Libs.LSM

local UPDATE_CONFIG = Constants.EVENTS.UPDATE_CONFIG

-- luacheck: push ignore 113
local CreateFont = CreateFont
-- luacheck: pop

function Fonts:OnInitialize()
  self.fonts = {}
end

function Fonts:OnEnable()
  -- GlassMessageFont
  self.fonts.GlassMessageFont = CreateFont("GlassMessageFont")
  self.fonts.GlassMessageFont:SetFont(
    LSM:Fetch(LSM.MediaType.FONT, Core.db.profile.font),
    Core.db.profile.messageFontSize,
    Core.db.profile.fontFlags
  )
  self.fonts.GlassMessageFont:SetShadowColor(0, 0, 0, 1)
  self.fonts.GlassMessageFont:SetShadowOffset(1, -1)
  self.fonts.GlassMessageFont:SetJustifyH("LEFT")
  self.fonts.GlassMessageFont:SetJustifyV("MIDDLE")
  self.fonts.GlassMessageFont:SetSpacing(Core.db.profile.messageLeading)

  -- GlassChatDockFont (tabs): its own font and size, from the Tabs options
  self.fonts.GlassChatDockFont = CreateFont("GlassChatDockFont")
  self:UpdateTabFont()
  self.fonts.GlassChatDockFont:SetShadowColor(0, 0, 0, 0)
  self.fonts.GlassChatDockFont:SetShadowOffset(1, -1)
  self.fonts.GlassChatDockFont:SetJustifyH("LEFT")
  self.fonts.GlassChatDockFont:SetJustifyV("MIDDLE")
  self.fonts.GlassChatDockFont:SetSpacing(3)

  -- GlassEditBoxFont
  self.fonts.GlassEditBoxFont = CreateFont("GlassEditBoxFont")
  self.fonts.GlassEditBoxFont:SetFont(
    LSM:Fetch(LSM.MediaType.FONT, Core.db.profile.font),
    Core.db.profile.editBoxFontSize,
    Core.db.profile.fontFlags
  )
  self.fonts.GlassEditBoxFont:SetShadowColor(0, 0, 0, 0)
  self.fonts.GlassEditBoxFont:SetShadowOffset(1, -1)
  self.fonts.GlassEditBoxFont:SetJustifyH("LEFT")
  self.fonts.GlassEditBoxFont:SetJustifyV("MIDDLE")
  self.fonts.GlassEditBoxFont:SetSpacing(3)

  Core:Subscribe(UPDATE_CONFIG, function (key)
    if key == "font" or key == "messageFontSize" then
      self.fonts.GlassMessageFont:SetFont(
        LSM:Fetch(LSM.MediaType.FONT, Core.db.profile.font),
        Core.db.profile.messageFontSize,
        Core.db.profile.fontFlags
      )
    end

    if key == "messageLeading" then
      self.fonts.GlassMessageFont:SetSpacing(Core.db.profile.messageLeading)
    end

    if key == "font" or key == "tabFont" or key == "tabFontSize" then
      self:UpdateTabFont()
    end

    if key == "font" or key == "editBoxFontSize" then
      self.fonts.GlassEditBoxFont:SetFont(
        LSM:Fetch(LSM.MediaType.FONT, Core.db.profile.font),
        Core.db.profile.editBoxFontSize,
        Core.db.profile.fontFlags
      )
    end
  end)
end

---
-- Font of the tabs: the Tabs font, or the messages font if none is chosen
function Fonts:UpdateTabFont()
  local profile = Core.db.profile
  local font = (profile.tabFont ~= nil and profile.tabFont ~= "") and profile.tabFont or profile.font
  self.fonts.GlassChatDockFont:SetFont(
    LSM:Fetch(LSM.MediaType.FONT, font),
    profile.tabFontSize or 12,
    profile.fontFlags
  )
end
