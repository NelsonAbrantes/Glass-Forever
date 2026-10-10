local Core, Constants = unpack(select(2, ...))
local OptionsPanel = Core:GetModule("OptionsPanel")

local LSM = Core.Libs.LSM

local OpenNews = Constants.ACTIONS.OpenNews
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
end

local function BuildEditBox(category, layout)
  local Settings = _G.Settings

  Header(layout, "Appearance")
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
  Slider(category, "chatHoldTime", "Fade out delay", 1, 180, 1, "Seconds before messages fade out")
  Checkbox(category, "chatShowOnMouseOver", "Show on mouse over", "Show faded messages again while the mouse is over the chat")
  Slider(category, "chatFadeInDuration", "Fade in duration", 0, 10, 0.05, nil, "chatFadeInDuration")
  Slider(category, "chatFadeOutDuration", "Fade out duration", 0, 10, 0.05, nil, "chatFadeOutDuration")
  Slider(category, "chatSlideInDuration", "Slide in duration", 0, 5, 0.05, "0 turns the animation off")

  Header(layout, "Misc")
  Checkbox(category, "indentWordWrap", "Indent on line wrap", "Adds an indent when a message wraps beyond a single line", "indentWordWrap")
  Checkbox(category, "shortChannelNames", "Short channel names", "[1] instead of [1. General], [P] instead of [Party], and so on. Applies to new messages")
  Checkbox(category, "keepHistory", "Keep chat history", "Saves the last 50 messages of each tab and shows them again when you log back in")
  Checkbox(category, "mouseOverTooltips", "Mouse over tooltips", "Show tooltips when hovering over chat links")
  Slider(category, "iconTextureYOffset", "Text icons Y offset", 0, 12, 1, "Adjust this if text icons aren't centered")
end

local function BuildTabs(category, layout)
  Header(layout, "Text")
  FontDropdown(layout, "tabFont", "Font", "Font of the tab names", "Same as messages")
  Slider(category, "tabFontSize", "Font size", 6, 32, 1, "Size of the tab names", "tabFontSize")

  Header(layout, "Tab bar")
  local positionSetting = ProfileSetting(category, "tabBarPosition", _G.Settings.VarType.String, "Position", "tabBarPosition")
  Dropdown(category, positionSetting, function ()
    return { { "top", "Above the messages" }, { "bottom", "Below the messages" } }
  end, "Where the tab bar sits")
  Slider(category, "tabBarOffsetX", "Horizontal offset", -100, 100, 1, "Moves the tab bar left (negative) or right (positive), in pixels", "tabBarOffsetX")
  Slider(category, "tabBarOffsetY", "Vertical offset", -50, 50, 1, "Moves the tab bar down (negative) or up (positive), in pixels", "tabBarOffsetY")
  Slider(category, "tabBarHeight", "Height", 14, 48, 1, "Height of the tab bar", "tabBarHeight")
  Slider(category, "tabPadding", "Spacing", 2, 40, 1, "Space around each tab name. More space makes the tabs wider", "tabPadding")
  Slider(category, "tabBarOpacity", "Background opacity", 0, 1, 0.05, "Opacity of the tab bar background", "tabBarOpacity")

  Header(layout, "Alerts")
  Checkbox(category, "tabAlerts", "Highlight new messages", "A tab glows in the color of the chat type when a message arrives and the tab is not selected, and the tab bar appears for a few seconds")
end

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

  Button(layout, "Own settings for this character", "Create profile", function ()
    db:SetProfile(db.keys.char)
  end, "Creates a profile named after this character and switches to it")

  Button(layout, "Reset the active profile", "Reset profile", function ()
    db:ResetProfile()
  end, "Puts all settings of the active profile back to their defaults")
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
