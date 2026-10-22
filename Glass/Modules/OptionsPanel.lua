local Core, Constants = unpack(select(2, ...))
local OptionsPanel = Core:GetModule("OptionsPanel")

local LSM = Core.Libs.LSM

local OpenNews = Constants.ACTIONS.OpenNews
local OpenSpamWords = Constants.ACTIONS.OpenSpamWords
local UnlockMover = Constants.ACTIONS.UnlockMover
local UpdateConfig = Constants.ACTIONS.UpdateConfig

-- luacheck: push ignore 113
local CreateFrame = CreateFrame
local CreateFromMixins = CreateFromMixins
-- luacheck: pop

local TITLE = "Glass Forever"

----
-- OptionsPanel Module
--
-- Builds the Glass pages in the game's Options window (Options > AddOns) with
-- the game's own controls, so they look like the rest of the game's options.
-- If the game doesn't support this, the Config module falls back to the
-- AceConfig pages.

local profile = function () return Core.db.profile end
local defaults = Core.defaults.profile

local function RoundTo2(value)
  return math.floor(value * 100 + 0.5) / 100
end

-- Small helpers around the game's Settings API

local function Header(layout, text)
  if _G.CreateSettingsListSectionHeaderInitializer then
    layout:AddInitializer(_G.CreateSettingsListSectionHeaderInitializer(text))
  end
end

-- A row with a label and a button in the current game style (red button with
-- a gold border), instead of the old Classic button the game uses by default
local function Button(layout, name, buttonText, onClick, tooltip)
  local Initializer = CreateFromMixins(
    _G.ScrollBoxFactoryInitializerMixin,
    _G.SettingsElementHierarchyMixin,
    _G.SettingsSearchableElementMixin
  )

  function Initializer:Init()
    _G.ScrollBoxFactoryInitializerMixin.Init(self, "SettingsListElementTemplate")
    self.data = { name = name, tooltip = tooltip }
    self:AddSearchTags(name, buttonText)
  end

  function Initializer:GetExtent()
    return 30
  end

  function Initializer:InitFrame(frame)
    frame:SetSize(280, 30)
    frame.data = self.data
    frame.Text:SetFontObject("GameFontNormal")
    frame.Text:SetText(name)
    frame.Text:SetPoint("LEFT", 37, 0)
    frame.Text:SetPoint("RIGHT", frame, "CENTER", -85, 0)

    if not frame.glassButton then
      frame.glassButton = Core.Components.CreateButton(frame)
      frame.glassButton:SetPoint("LEFT", frame, "CENTER", -80, 0)
    end

    local button = frame.glassButton
    button:SetText(buttonText)
    button:SetScript("OnClick", onClick)
    button:Show()
  end

  function Initializer:Resetter(frame)
    if frame.glassButton then
      frame.glassButton:Hide()
    end
  end

  local initializer = CreateFromMixins(Initializer)
  initializer:Init()
  layout:AddInitializer(initializer)
end

-- A setting stored in the Glass profile. configKey is the UpdateConfig event
-- to send after a change (nil if the setting is read when needed).
local function ProfileSetting(category, key, varType, name, configKey, round)
  return _G.Settings.RegisterProxySetting(
    category,
    "GLASS_"..key:upper(),
    varType,
    name,
    defaults[key],
    function () return profile()[key] end,
    function (value)
      if round then value = RoundTo2(value) end
      profile()[key] = value
      if configKey then
        Core:Dispatch(UpdateConfig(configKey))
      end
    end
  )
end

local function Slider(category, key, name, minValue, maxValue, step, tooltip, configKey)
  local Settings = _G.Settings
  local decimals = step < 1
  local setting = ProfileSetting(category, key, Settings.VarType.Number, name, configKey, decimals)
  local options = Settings.CreateSliderOptions(minValue, maxValue, step)
  options:SetLabelFormatter(_G.MinimalSliderWithSteppersMixin.Label.Right, function (value)
    return decimals and RoundTo2(value) or value
  end)
  Settings.CreateSlider(category, setting, options, tooltip)
end

local function Checkbox(category, key, name, tooltip, configKey)
  local Settings = _G.Settings
  local setting = ProfileSetting(category, key, Settings.VarType.Boolean, name, configKey)
  Settings.CreateCheckbox(category, setting, tooltip)
end

local function Dropdown(category, setting, values, tooltip)
  local Settings = _G.Settings
  Settings.CreateDropdown(category, setting, function ()
    local container = Settings.CreateControlTextContainer()
    for _, entry in ipairs(values()) do
      container:Add(entry[1], entry[2])
    end
    return container:GetData()
  end, tooltip)
end

-- Font list with scrolling: there can be many fonts, more than fit on screen.
-- key is the profile setting. With sameLabel, the list starts with an entry
-- that stores "" (e.g. "Same as messages").
local function FontDropdown(layout, key, label, tooltip, sameLabel)
  key = key or "font"
  label = label or "Font"

  local function Shown(value)
    if value == "" and sameLabel then return sameLabel end
    return value
  end

  local Initializer = CreateFromMixins(
    _G.ScrollBoxFactoryInitializerMixin,
    _G.SettingsElementHierarchyMixin,
    _G.SettingsSearchableElementMixin
  )

  function Initializer:Init()
    _G.ScrollBoxFactoryInitializerMixin.Init(self, "SettingsListElementTemplate")
    self.data = { name = label, tooltip = tooltip or "Font used throughout Glass Forever" }
    self:AddSearchTags(label)
  end

  function Initializer:GetExtent()
    return 26
  end

  function Initializer:InitFrame(frame)
    frame:SetSize(280, 26)
    frame.data = self.data
    frame.Text:SetFontObject("GameFontNormal")
    frame.Text:SetText(label)
    frame.Text:SetPoint("LEFT", 37, 0)
    frame.Text:SetPoint("RIGHT", frame, "CENTER", -85, 0)

    if not frame.glassFontDropdown then
      local dropdown = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
      dropdown:SetPoint("LEFT", frame, "CENTER", -80, 0)
      dropdown:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
      dropdown:SetHeight(26)
      frame.glassFontDropdown = dropdown
    end

    local dropdown = frame.glassFontDropdown
    dropdown:Show()
    dropdown:SetupMenu(function (_, rootDescription)
      rootDescription:SetScrollMode(300)
      -- A copy: LSM's list is shared with other addons
      local fonts = {}
      if sameLabel then
        table.insert(fonts, "")
      end
      for _, font in ipairs(LSM:List("font")) do
        table.insert(fonts, font)
      end
      for _, font in ipairs(fonts) do
        rootDescription:CreateRadio(
          Shown(font),
          function (value) return (profile()[key] or "") == value end,
          function (value)
            profile()[key] = value
            Core:Dispatch(UpdateConfig(key))
            dropdown:OverrideText(Shown(value))
          end,
          font
        )
      end
    end)
    dropdown:OverrideText(Shown(profile()[key] or ""))
  end

  function Initializer:Resetter(frame)
    if frame.glassFontDropdown then
      frame.glassFontDropdown:Hide()
    end
  end

  local initializer = CreateFromMixins(Initializer)
  initializer:Init()
  layout:AddInitializer(initializer)
end

----
-- Pages

local function BuildGeneral(category, layout)
  local Settings = _G.Settings

  Header(layout, "Info")
  Button(layout, "Version: "..Core.Version, "What's new", function ()
    Core:Dispatch(OpenNews())
  end, "Show the version history")
  Button(layout, "Move the chat", "Unlock frame", function ()
    Core:Dispatch(UnlockMover())
  end, "Drag the chat to a new place. You can also move it in Edit Mode.")

  Header(layout, "Appearance")
  FontDropdown(layout)

  local flagSetting = ProfileSetting(category, "fontFlags", Settings.VarType.String, "Font outline", "font")
  Dropdown(category, flagSetting, function ()
    return {
      { "", "None" },
      { "OUTLINE", "Outline" },
      { "OUTLINE, MONOCHROME", "Outline Monochrome" },
    }
  end, "Outline around the letters")

  Header(layout, "Frame")
  Slider(category, "frameWidth", "Width", 100, 2000, 1, "Width of the chat", "frameWidth")
  Slider(category, "frameHeight", "Height", 100, 1200, 1, "Height of the chat", "frameHeight")

  Header(layout, "Alerts")
  Checkbox(category, "alertStyle", "Glass look for game alerts", "Achievements, loot, money, new recipes and the game's other alerts get the Glass background, a gold line and the Glass font instead of their own art (the Battle.net alert always has it)")

  Header(layout, "Separate windows")
  Checkbox(category, "windowStyle", "Glass look", "Tabs dragged out of the chat become windows with the Glass look: no border, the Glass background while the mouse is over them, and messages that fade out. Off: they look like the default chat", "windowStyle")
  local openSetting = ProfileSetting(category, "windowOpenPosition", Settings.VarType.String, "Opens at")
  Dropdown(category, openSetting, function ()
    return {
      { "above", "Above the chat" },
      { "right", "Right of the chat" },
      { "left", "Left of the chat" },
      { "center", "Middle of the screen" },
    }
  end, "Where a window opened with \"Open in Separate Window\" (right click a channel in the chat) appears. It opens unlocked, so it can be moved right away")

  Header(layout, "Chat buttons")
  Checkbox(category, "chatButtons", "Show chat buttons", "Show the game's chat buttons (friends, channels and voice chat, emotes and languages) beside the chat. They appear and fade with the tab bar", "chatButtons")
  local sideSetting = ProfileSetting(category, "chatButtonsSide", Settings.VarType.String, "Position", "chatButtonsSide")
  Dropdown(category, sideSetting, function ()
    return {
      { "left", "Left" },
      { "right", "Right" },
      { "topleft", "Top left" },
      { "topright", "Top right" },
      { "bottomleft", "Bottom left" },
      { "bottomright", "Bottom right" },
    }
  end, "Where the buttons are: in a column beside the chat, or in a row above or below it")
end

local function BuildEditBox(category, layout)
  local Settings = _G.Settings

  Header(layout, "Appearance")
  local styleSetting = ProfileSetting(category, "editBoxStyle", Settings.VarType.String, "Style", "editBoxStyle")
  Dropdown(category, styleSetting, function ()
    return { { "minimal", "Minimal" }, { "solid", "Solid" }, { "framed", "Framed" } }
  end, "Minimal: fades out at the ends like the messages, with a thin line in the color of the chat you're typing in (say, party, whisper...). Solid: a plain dark box. Framed: rounded corners and a border in the chat's color")
  Slider(category, "editBoxFontSize", "Font size", 6, 48, 1, nil, "editBoxFontSize")
  Slider(category, "editBoxBackgroundOpacity", "Background opacity", 0, 1, 0.05, nil, "editBoxBackgroundOpacity")

  Header(layout, "Position")
  local positionSetting = Settings.RegisterProxySetting(
    category, "GLASS_EDITBOX_POSITION", Settings.VarType.String, "Position",
    defaults.editBoxAnchor.position,
    function () return profile().editBoxAnchor.position end,
    function (value)
      local anchor = profile().editBoxAnchor
      anchor.position = value
      anchor.yOfs = value == "ABOVE" and 5 or -5
      Core:Dispatch(UpdateConfig("editBoxAnchor"))
    end
  )
  Dropdown(category, positionSetting, function ()
    return { { "ABOVE", "Above the chat" }, { "BELOW", "Below the chat" } }
  end, "Where the box you type in appears")

  local offsetSetting = Settings.RegisterProxySetting(
    category, "GLASS_EDITBOX_OFFSET", Settings.VarType.Number, "Vertical offset",
    defaults.editBoxAnchor.yOfs,
    function () return profile().editBoxAnchor.yOfs end,
    function (value)
      profile().editBoxAnchor.yOfs = value
      Core:Dispatch(UpdateConfig("editBoxAnchor"))
    end
  )
  local offsetOptions = Settings.CreateSliderOptions(-30, 30, 1)
  offsetOptions:SetLabelFormatter(_G.MinimalSliderWithSteppersMixin.Label.Right, function (value) return value end)
  Settings.CreateSlider(category, offsetSetting, offsetOptions, "Space between the chat and the edit box")
end

local function BuildMessages(category, layout)
  Header(layout, "Appearance")
  Slider(category, "messageFontSize", "Font size", 6, 48, 1, nil, "messageFontSize")
  Slider(category, "chatBackgroundOpacity", "Background opacity", 0, 1, 0.05, nil, "chatBackgroundOpacity")
  Slider(category, "messageLeading", "Leading", 0, 10, 1, "Space between the lines of a message", "messageLeading")
  Slider(category, "messageLinePadding", "Line padding", 0, 2, 0.05, "Space around each message", "messageLinePadding")

  Header(layout, "Animations")
  Checkbox(category, "messageFade", "Fade out", "Messages fade out after a while when you're not using the chat. Turn off to keep them always visible", "messageFade")
  Slider(category, "chatHoldTime", "Fade out delay", 1, 180, 1, "Seconds before messages fade out", "chatHoldTime")
  Checkbox(category, "chatShowOnMouseOver", "Show on mouse over", "Show faded messages again while the mouse is over the chat")
  Slider(category, "chatFadeInDuration", "Fade in duration", 0, 10, 0.05, nil, "chatFadeInDuration")
  Slider(category, "chatFadeOutDuration", "Fade out duration", 0, 10, 0.05, nil, "chatFadeOutDuration")
  Slider(category, "chatSlideInDuration", "Slide in duration", 0, 5, 0.05, "0 turns the animation off")

  Header(layout, "Spam filter")
  Checkbox(category, "spamFilter", "Hide spam", "Hide messages that contain any of the blocked words, like gold sellers. Applies to new messages")
  Button(layout, "Blocked words", "Edit list", function ()
    Core:Dispatch(OpenSpamWords())
  end, "Words and phrases that hide a message. Comes with a few gold seller phrases; add or remove what you like.")

  Header(layout, "Misc")
  Checkbox(category, "indentWordWrap", "Indent on line wrap", "Adds an indent when a message wraps beyond a single line", "indentWordWrap")
  Checkbox(category, "shortChannelNames", "Short channel names", "[1] instead of [1. General], [P] instead of [Party], and so on. Applies to new messages")
  local emoteSetting = ProfileSetting(category, "emoteStyle", _G.Settings.VarType.String, "Emotes", "emoteStyle")
  Dropdown(category, emoteSetting, function ()
    return {
      { "glass", "Glass (gold outlines)" },
      { "classic", "Classic (yellow faces)" },
      { "off", "Off (text)" },
    }
  end, ":) :( :D ;) :P :O :| :/ xD <3 </3 D: :S :* B) :'( >:( ^^ -_- o.O :3 T_T :$ written in a message show as small faces. Only players with Glass see them; the others see the text. Applies to new messages")
  Checkbox(category, "emoteButton", "Emote button", "A small face at the right of the chat box: click it to pick an emote. The emotes still show in the chat without it", "emoteButton")
  local timeSetting = ProfileSetting(category, "timestamps", _G.Settings.VarType.String, "Timestamps")
  Dropdown(category, timeSetting, function ()
    return {
      { "off", "Off" },
      { "hm", "17:49" },
      { "hms", "17:49:05" },
    }
  end, "The time a message arrived, in front of it. Shift+click the time to write the message in the chat box (nothing is sent), click it to copy it. Applies to new messages")
  Checkbox(category, "chatClassIcons", "Class icons", "A small class icon in front of players' names. Applies to new messages")
  Checkbox(category, "chatRaceIcons", "Race icons", "A small race icon in front of players' names (races the game has no icon for get none). Applies to new messages")
  Checkbox(category, "firstNamesOnly", "First names only", "\"Aehya\" instead of \"Aehya Bfc\": shorter names in the chat. Whispers still go to the full name. Applies to new messages")
  Checkbox(category, "keepHistory", "Keep chat history", "Saves the last 50 messages of each tab and shows them again when you log back in")
  Checkbox(category, "arrowKeyHistory", "Arrow keys history", "Up and Down arrows in the chat box go through what you typed, even before logging out or /reload, without holding Alt")
  Checkbox(category, "mouseOverTooltips", "Mouse over tooltips", "Show tooltips when hovering over chat links")
  Slider(category, "iconTextureYOffset", "Text icons Y offset", 0, 12, 1, "Adjust this if text icons aren't centered")
end

local function BuildTabs(category, layout)
  local Settings = _G.Settings

  Header(layout, "Style")
  local styleSetting = ProfileSetting(category, "tabStyle", Settings.VarType.String, "Tab style", "tabStyle")
  Dropdown(category, styleSetting, function ()
    return {
      { "minimal", "Minimal" },
      { "framed", "Framed" },
      { "solid", "Solid" },
      { "underline", "Underline" },
      { "pill", "Pill" },
      { "glossy", "Glossy" },
      { "classic", "Classic" },
    }
  end, "Minimal: only the names, with a line on the selected tab.\nFramed: rounded background with a bronze border.\nSolid: filled tabs, the selected one in the accent color.\nUnderline: a bar under the selected tab.\nPill: capsule-shaped tabs.\nGlossy: raised, shiny buttons.\nClassic: the game's own tabs.")

  local accentSetting = ProfileSetting(category, "tabAccent", Settings.VarType.String, "Accent color", "tabAccent")
  Dropdown(category, accentSetting, function ()
    return {
      { "default", "Style default" },
      { "bronze", "Bronze" },
      { "gold", "Gold" },
      { "cyan", "Cyan" },
      { "silver", "Silver" },
      { "green", "Green" },
      { "purple", "Purple" },
      { "red", "Red" },
      { "class", "Class color" },
    }
  end, "Color of the selected tab: its border, bar, line or background, depending on the style. Class color: the color of your character's class.")

  local lineAnimSetting = ProfileSetting(category, "tabLineAnimation", Settings.VarType.String, "Selected tab animation", "tabLineAnimation")
  Dropdown(category, lineAnimSetting, function ()
    return {
      { "slide", "Slide" },
      { "grow", "Grow" },
      { "off", "Off" },
    }
  end, "When you select another tab.\nSlide: the line (Minimal) or bar (Underline) slides from the old tab to the new one.\nGrow: it opens from the middle of the new tab.\nFramed, Solid, Pill and Glossy fade softly from tab to tab with either.\nOff: no animation.")

  Header(layout, "Text")
  FontDropdown(layout, "tabFont", "Font", "Font of the tab names", "Same as messages")
  Slider(category, "tabFontSize", "Font size", 6, 32, 1, "Size of the tab names", "tabFontSize")
  local textColorSetting = ProfileSetting(category, "tabTextColor", Settings.VarType.String, "Name color", "tabTextColor")
  Dropdown(category, textColorSetting, function ()
    return {
      { "auto", "Auto" },
      { "gold", "Gold" },
      { "white", "White" },
      { "silver", "Silver" },
      { "dark", "Dark" },
    }
  end, "Color of the tab names. Auto: gold, and on the Solid style the selected tab gets a color that stands out from its background. Whisper tabs keep the whisper color.")

  Header(layout, "Tab bar")
  local positionSetting = ProfileSetting(category, "tabBarPosition", _G.Settings.VarType.String, "Position", "tabBarPosition")
  Dropdown(category, positionSetting, function ()
    return { { "top", "Above the messages" }, { "bottom", "Below the messages" } }
  end, "Where the tab bar sits")
  local alignSetting = ProfileSetting(category, "tabAlign", _G.Settings.VarType.String, "Alignment", "tabAlign")
  Dropdown(category, alignSetting, function ()
    return { { "left", "Left" }, { "center", "Center" }, { "right", "Right" } }
  end, "Where the tabs sit along the tab bar")
  Checkbox(category, "tabBarFade", "Fade out", "The tab bar fades out with the chat when you're not using it. Turn off to keep it always visible", "tabBarFade")
  Slider(category, "tabBarOffsetX", "Horizontal offset", -100, 100, 1, "Moves the tab bar left (negative) or right (positive), in pixels", "tabBarOffsetX")
  Slider(category, "tabBarOffsetY", "Vertical offset", -50, 50, 1, "Moves the tab bar down (negative) or up (positive), in pixels", "tabBarOffsetY")
  Slider(category, "tabBarHeight", "Height", 14, 48, 1, "Height of the tab bar", "tabBarHeight")
  Slider(category, "tabPadding", "Spacing", 2, 40, 1, "Space around each tab name. More space makes the tabs wider", "tabPadding")
  Slider(category, "tabBarOpacity", "Background opacity", 0, 1, 0.05, "Opacity of the tab bar background", "tabBarOpacity")

  Header(layout, "Alerts")
  Checkbox(category, "tabAlerts", "Highlight new messages", "A tab glows in the color of the chat type when a guild, party, raid or whisper message arrives and the tab is not selected, and the tab bar appears for a few seconds")
  Checkbox(category, "tabUnreadCount", "Unread count", "A small number by the name of a tab you're not looking at: how many messages came in since you last looked", "tabUnreadCount")
end

----
-- Profile as text (Profiles page): Export shows the active profile as one
-- line of text to copy and share; Import reads such a line back into the
-- active profile. Only letters and digits, so it survives being pasted
-- anywhere; reading it never runs any code.
local EXPORT_PREFIX = "GlassForever1:"
local MAX_DEPTH = 10

local function Hex(text)
  return (text:gsub(".", function (c) return string.format("%02x", c:byte()) end))
end

local function Serialize(value, out, depth)
  local kind = type(value)
  if kind == "string" then
    out[#out + 1] = "s"..Hex(value)..";"
  elseif kind == "number" then
    out[#out + 1] = "n"..Hex(tostring(value))..";"
  elseif kind == "boolean" then
    out[#out + 1] = value and "T" or "F"
  elseif kind == "table" and depth < MAX_DEPTH then
    out[#out + 1] = "{"
    for key, inner in pairs(value) do
      local keyKind, innerKind = type(key), type(inner)
      if (keyKind == "string" or keyKind == "number")
        and (innerKind == "string" or innerKind == "number" or innerKind == "boolean" or innerKind == "table") then
        Serialize(key, out, depth + 1)
        Serialize(inner, out, depth + 1)
      end
    end
    out[#out + 1] = "}"
  end
end

local function ExportProfile()
  local out = {}
  Serialize(Core.db.profile, out, 0)
  return EXPORT_PREFIX..table.concat(out)
end

-- Reads one value from position i; returns it and the next position, or nil
local function Parse(text, i, depth)
  local c = text:sub(i, i)
  if c == "s" or c == "n" then
    local stop = text:find(";", i + 1, true)
    local hex = stop and text:sub(i + 1, stop - 1)
    if not hex or #hex % 2 == 1 or hex:find("[^%x]") then return nil end
    local raw = hex:gsub("%x%x", function (h) return string.char(tonumber(h, 16)) end)
    if c == "n" then
      local number = tonumber(raw)
      if not number then return nil end
      return number, stop + 1
    end
    return raw, stop + 1
  elseif c == "T" then
    return true, i + 1
  elseif c == "F" then
    return false, i + 1
  elseif c == "{" and depth < MAX_DEPTH then
    local result = {}
    i = i + 1
    while text:sub(i, i) ~= "}" do
      if i > #text then return nil end
      local key, nextI = Parse(text, i, depth + 1)
      if key == nil or (type(key) ~= "string" and type(key) ~= "number") then return nil end
      local inner
      inner, nextI = Parse(text, nextI, depth + 1)
      if inner == nil then return nil end
      result[key] = inner
      i = nextI
    end
    return result, i + 1
  end
  return nil
end

local function ImportProfile(text)
  text = (text or ""):gsub("%s", "")
  if text:sub(1, #EXPORT_PREFIX) ~= EXPORT_PREFIX then return false end
  local data, nextI = Parse(text, #EXPORT_PREFIX + 1, 0)
  if type(data) ~= "table" or nextI ~= #text + 1 then return false end
  local profile = Core.db.profile
  for key in pairs(profile) do profile[key] = nil end -- back to the defaults
  for key, value in pairs(data) do profile[key] = value end
  return true
end

local importWindow
local function OpenImport()
  if not importWindow then
    local frame = CreateFrame("Frame", "GlassImportFrame", _G.UIParent, "DefaultPanelFlatTemplate")
    frame:SetSize(520, 220)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    table.insert(_G.UISpecialFrames, "GlassImportFrame")
    frame:SetTitle("Glass Forever: Import profile")
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 7, -3)
    bg:SetPoint("BOTTOMRIGHT", -3, 3)
    bg:SetColorTexture(0.08, 0.08, 0.08, 1)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetFrameLevel((frame.TitleContainer or frame):GetFrameLevel() + 10)
    close:SetPoint("TOPRIGHT")
    local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 18, -34)
    hint:SetPoint("TOPRIGHT", -18, -34)
    hint:SetJustifyH("LEFT")
    hint:SetText("Paste a profile (Ctrl+V). It replaces the settings of the active profile.")
    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -56)
    scroll:SetPoint("BOTTOMRIGHT", -36, 44)
    local input = CreateFrame("EditBox", nil, scroll)
    input:SetMultiLine(true)
    input:SetAutoFocus(false)
    input:SetFontObject("ChatFontNormal")
    input:SetWidth(scroll:GetWidth())
    input:SetScript("OnEscapePressed", function () frame:Hide() end)
    scroll:SetScrollChild(input)
    scroll:SetScript("OnSizeChanged", function (_, width) input:SetWidth(width) end)
    local status = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    status:SetPoint("BOTTOMLEFT", 18, 18)
    local apply = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    apply:SetSize(120, 22)
    apply:SetPoint("BOTTOMRIGHT", -14, 12)
    apply:SetText("Import")
    apply:SetScript("OnClick", function ()
      if ImportProfile(input:GetText()) then
        frame:Hide()
        _G.StaticPopup_Show("GLASS_PROFILE_IMPORTED")
      else
        status:SetText("|cffff6060That isn't a Glass Forever profile.|r")
      end
    end)
    frame.input, frame.status = input, status
    importWindow = frame
  end
  importWindow.input:SetText("")
  importWindow.status:SetText("")
  importWindow:Show()
  importWindow.input:SetFocus()
end

_G.StaticPopupDialogs["GLASS_PROFILE_IMPORTED"] = {
  text = "Glass Forever: profile imported. Reload the interface to use it?",
  button1 = _G.ACCEPT or "Reload",
  button2 = _G.CANCEL or "Later",
  OnAccept = function () _G.ReloadUI() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

-- "Create profile": asks for the new profile's name (this character's name
-- is written in to start with)
local function PopupEditBox(dialog)
  return dialog.editBox or dialog.EditBox or (dialog.GetEditBox and dialog:GetEditBox())
end

local function CreateNamedProfile(dialog)
  local box = PopupEditBox(dialog)
  local name = box and strtrim(box:GetText() or "")
  if name and name ~= "" then
    Core.db:SetProfile(name)
  end
end

_G.StaticPopupDialogs["GLASS_NEW_PROFILE"] = {
  text = "Glass Forever: name of the new profile",
  button1 = _G.CREATE or "Create",
  button2 = _G.CANCEL or "Cancel",
  hasEditBox = true,
  maxLetters = 48,
  OnShow = function (self)
    local box = PopupEditBox(self)
    if box then
      box:SetText(Core.db.keys.char)
      box:HighlightText()
      box:SetFocus()
    end
  end,
  OnAccept = CreateNamedProfile,
  EditBoxOnEnterPressed = function (self)
    local dialog = self:GetParent()
    CreateNamedProfile(dialog)
    dialog:Hide()
  end,
  EditBoxOnEscapePressed = function (self) self:GetParent():Hide() end,
  timeout = 0,
  whileDead = true,
  hideOnEscape = true,
}

local function BuildProfiles(category, layout)
  local Settings = _G.Settings
  local db = Core.db

  local profileSetting = Settings.RegisterProxySetting(
    category, "GLASS_PROFILE", Settings.VarType.String, "Active profile",
    "Default",
    function () return db:GetCurrentProfile() end,
    function (value) db:SetProfile(value) end
  )
  Dropdown(category, profileSetting, function ()
    local list = {}
    for _, name in ipairs(db:GetProfiles()) do
      table.insert(list, { name, name })
    end
    return list
  end, "Settings are saved in profiles. Characters can share a profile or have their own.")

  Button(layout, "New profile", "Create profile", function ()
    _G.StaticPopup_Show("GLASS_NEW_PROFILE")
  end, "Asks for a name, then creates a profile with that name (with the default settings) and switches to it")

  Button(layout, "Reset the active profile", "Reset profile", function ()
    db:ResetProfile()
  end, "Puts all settings of the active profile back to their defaults")

  Button(layout, "Share your settings", "Export profile", function ()
    Core:Dispatch(Constants.ACTIONS.OpenCopy({
      title = "Glass Forever: Export profile", text = ExportProfile(), height = 220,
    }))
  end, "Shows the active profile as text: copy it (Ctrl+C) to keep it or share it")

  Button(layout, "Use shared settings", "Import profile", OpenImport,
    "Paste a profile made with Export profile; it replaces the settings of the active profile")
end

----
-- Returns the category ID to open the Glass pages, or raises an error if the
-- game's Settings API is missing something (the caller falls back then)
function OptionsPanel:Build()
  local Settings = _G.Settings
  assert(Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting,
    "Settings API not available")

  local category, layout = Settings.RegisterVerticalLayoutCategory(TITLE)
  BuildGeneral(category, layout)

  local editBox, editBoxLayout = Settings.RegisterVerticalLayoutSubcategory(category, "Edit box")
  BuildEditBox(editBox, editBoxLayout)

  local tabs, tabsLayout = Settings.RegisterVerticalLayoutSubcategory(category, "Tabs")
  BuildTabs(tabs, tabsLayout)

  local messages, messagesLayout = Settings.RegisterVerticalLayoutSubcategory(category, "Messages")
  BuildMessages(messages, messagesLayout)

  local profiles, profilesLayout = Settings.RegisterVerticalLayoutSubcategory(category, "Profiles")
  BuildProfiles(profiles, profilesLayout)

  Settings.RegisterAddOnCategory(category)
  return category:GetID()
end
