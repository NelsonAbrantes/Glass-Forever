local Core, Constants = unpack(select(2, ...))
local Fonts = Core:GetModule("Fonts")

local LSM = Core.Libs.LSM

local UPDATE_CONFIG = Constants.EVENTS.UPDATE_CONFIG

-- luacheck: push ignore 113
local CreateFont = CreateFont
local CreateFontFamily = CreateFontFamily
-- luacheck: pop

-- The chosen font has the Latin letters; the others come from the game's own
-- chat font. Most fonts have no Chinese or Korean letters (they showed as
-- squares), and some no Cyrillic ones.
local ALPHABETS = { "roman", "korean", "simplifiedchinese", "traditionalchinese", "russian" }

-- The game's chat font file for an alphabet, if it has one
local function GameFile(alphabet)
  local chatFont = _G.ChatFontNormal
  local member = chatFont and chatFont.GetFontObjectForAlphabet and chatFont:GetFontObjectForAlphabet(alphabet)
  return member and (member:GetFont())
end

local function FileFor(alphabet, file)
  if alphabet == "roman" then return file end
  return GameFile(alphabet) or file
end

-- Each font object of a font: the font itself and, for a family, the one of
-- each alphabet
local function EachPart(font, callback)
  callback(font)
  if font.GetFontObjectForAlphabet then
    for _, alphabet in ipairs(ALPHABETS) do
      local member = font:GetFontObjectForAlphabet(alphabet)
      if member and member ~= font then callback(member, alphabet) end
    end
  end
end

---
-- Creates the named font the first time, as a family with the game's fonts
-- for other alphabets when the game allows it, and sets its file, size and
-- outline. Returns the font.
function Fonts:Set(name, file, size, flags)
  local font = _G[name]
  if not font then
    if CreateFontFamily and GameFile("simplifiedchinese") then
      local members = {}
      for _, alphabet in ipairs(ALPHABETS) do
        table.insert(members, { alphabet = alphabet, file = FileFor(alphabet, file), height = size, flags = flags })
      end
      local ok, family = pcall(CreateFontFamily, name, members)
      if ok and family then font = family end
    end
    font = font or CreateFont(name)
  end

  EachPart(font, function (part, alphabet)
    part:SetFont(FileFor(alphabet or "roman", file), size, flags)
  end)
  return font
end

-- The same look for every part of a font
local function Style(font, shadowAlpha, spacing)
  EachPart(font, function (part)
    part:SetShadowColor(0, 0, 0, shadowAlpha)
    part:SetShadowOffset(1, -1)
    part:SetJustifyH("LEFT")
    part:SetJustifyV("MIDDLE")
    part:SetSpacing(spacing)
  end)
end

local function Fetch(font)
  return LSM:Fetch(LSM.MediaType.FONT, font)
end

function Fonts:OnInitialize()
  self.fonts = {}
end

function Fonts:UpdateMessageFont()
  local profile = Core.db.profile
  self.fonts.GlassMessageFont = self:Set("GlassMessageFont", Fetch(profile.font), profile.messageFontSize, profile.fontFlags)
  Style(self.fonts.GlassMessageFont, 1, profile.messageLeading)
end

function Fonts:UpdateEditBoxFont()
  local profile = Core.db.profile
  self.fonts.GlassEditBoxFont = self:Set("GlassEditBoxFont", Fetch(profile.font), profile.editBoxFontSize, profile.fontFlags)
  Style(self.fonts.GlassEditBoxFont, 0, 3)
end

function Fonts:OnEnable()
  self:UpdateMessageFont()
  -- GlassChatDockFont (tabs): its own font and size, from the Tabs options
  self:UpdateTabFont()
  self:UpdateEditBoxFont()

  Core:Subscribe(UPDATE_CONFIG, function (key)
    if key == "font" or key == "messageFontSize" or key == "messageLeading" then
      self:UpdateMessageFont()
    end

    if key == "font" or key == "tabFont" or key == "tabFontSize" then
      self:UpdateTabFont()
    end

    if key == "font" or key == "editBoxFontSize" then
      self:UpdateEditBoxFont()
    end
  end)
end

---
-- Font of the tabs: the Tabs font, or the messages font if none is chosen
function Fonts:UpdateTabFont()
  local profile = Core.db.profile
  local font = (profile.tabFont ~= nil and profile.tabFont ~= "") and profile.tabFont or profile.font
  self.fonts.GlassChatDockFont = self:Set("GlassChatDockFont", Fetch(font), profile.tabFontSize or 12, profile.fontFlags)
  Style(self.fonts.GlassChatDockFont, 0, 3)
end
