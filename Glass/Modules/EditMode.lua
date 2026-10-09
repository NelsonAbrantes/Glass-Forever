local Core, Constants = unpack(select(2, ...))
local EditMode = Core:GetModule("EditMode")

local LSM = Core.Libs.LSM

local SaveFramePosition = Constants.ACTIONS.SaveFramePosition
local UpdateConfig = Constants.ACTIONS.UpdateConfig

-- luacheck: push ignore 113
local EditModeManagerFrame = EditModeManagerFrame
local LibStub = LibStub
-- luacheck: pop

----
-- EditMode Module
--
-- Registers the Glass frame with Blizzard's Edit Mode (through LibEditMode),
-- so it can be moved and its basic options changed like any other UI frame.
-- The settings are the same values used by the /glass options panel, so a
-- change in one place shows up in the other.
function EditMode:OnEnable()
  local LEM = LibStub and LibStub("LibEditMode", true)
  if not LEM or not EditModeManagerFrame then
    -- Client without Edit Mode: keep using /glass lock to move the frame
    return
  end

  local AceConfigRegistry = LibStub("AceConfigRegistry-3.0", true)
  local moverFrame = Core:GetModule("UIManager").moverFrame
  local profile = function () return Core.db.profile end
  local defaults = Core.defaults.profile

  -- Applies a setting and keeps the /glass panel in sync
  local function Set(key, value, configKey)
    profile()[key] = value
    if configKey then
      Core:Dispatch(UpdateConfig(configKey))
    end
    if AceConfigRegistry then
      AceConfigRegistry:NotifyChange("Glass")
    end
  end

  local function RoundTo2(value)
    return math.floor(value * 100 + 0.5) / 100
  end

  -- Position
  local defaultAnchor = defaults.positionAnchor
  LEM:AddFrame(moverFrame, function (_, _, point, x, y)
    Core:Dispatch(SaveFramePosition({ point = point, xOfs = x, yOfs = y }))
    Core:Dispatch(UpdateConfig("framePosition"))
    if AceConfigRegistry then
      AceConfigRegistry:NotifyChange("Glass")
    end
  end, { point = defaultAnchor.point, x = defaultAnchor.xOfs, y = defaultAnchor.yOfs }, "Glass")

  -- Settings shown in the Edit Mode dialog
  LEM:AddFrameSettings(moverFrame, {
    {
      name = "Width",
      kind = LEM.SettingType.Slider,
      default = defaults.frameWidth,
      minValue = 200,
      maxValue = 1200,
      valueStep = 1,
      get = function () return profile().frameWidth end,
      set = function (_, value) Set("frameWidth", value, "frameWidth") end,
    },
    {
      name = "Height",
      kind = LEM.SettingType.Slider,
      default = defaults.frameHeight,
      minValue = 100,
      maxValue = 800,
      valueStep = 1,
      get = function () return profile().frameHeight end,
      set = function (_, value) Set("frameHeight", value, "frameHeight") end,
    },
    {
      name = "Font",
      kind = LEM.SettingType.Dropdown,
      default = defaults.font,
      height = 300,
      values = function ()
        local fonts = {}
        for _, name in ipairs(LSM:List("font")) do
          table.insert(fonts, { text = name })
        end
        return fonts
      end,
      get = function () return profile().font end,
      set = function (_, value) Set("font", value, "font") end,
    },
    {
      name = "Message font size",
      kind = LEM.SettingType.Slider,
      default = defaults.messageFontSize,
      minValue = 6,
      maxValue = 32,
      valueStep = 1,
      get = function () return profile().messageFontSize end,
      set = function (_, value) Set("messageFontSize", value, "messageFontSize") end,
    },
    {
      name = "Edit box font size",
      kind = LEM.SettingType.Slider,
      default = defaults.editBoxFontSize,
      minValue = 6,
      maxValue = 32,
      valueStep = 1,
      get = function () return profile().editBoxFontSize end,
      set = function (_, value) Set("editBoxFontSize", value, "editBoxFontSize") end,
    },
    {
      name = "Background opacity",
      kind = LEM.SettingType.Slider,
      default = defaults.chatBackgroundOpacity,
      minValue = 0,
      maxValue = 1,
      valueStep = 0.05,
      formatter = RoundTo2,
      get = function () return profile().chatBackgroundOpacity end,
      set = function (_, value)
        Set("chatBackgroundOpacity", RoundTo2(value), "chatBackgroundOpacity")
      end,
    },
    {
      name = "Fade out delay",
      desc = "Seconds before messages fade out",
      kind = LEM.SettingType.Slider,
      default = defaults.chatHoldTime,
      minValue = 1,
      maxValue = 60,
      valueStep = 1,
      get = function () return profile().chatHoldTime end,
      set = function (_, value) Set("chatHoldTime", value) end,
    },
    {
      name = "Fade in duration",
      desc = "Seconds a new message takes to appear",
      kind = LEM.SettingType.Slider,
      default = defaults.chatFadeInDuration,
      minValue = 0,
      maxValue = 5,
      valueStep = 0.05,
      formatter = RoundTo2,
      get = function () return profile().chatFadeInDuration end,
      set = function (_, value)
        Set("chatFadeInDuration", RoundTo2(value), "chatFadeInDuration")
      end,
    },
    {
      name = "Fade out duration",
      desc = "Seconds a message takes to disappear",
      kind = LEM.SettingType.Slider,
      default = defaults.chatFadeOutDuration,
      minValue = 0,
      maxValue = 5,
      valueStep = 0.05,
      formatter = RoundTo2,
      get = function () return profile().chatFadeOutDuration end,
      set = function (_, value)
        Set("chatFadeOutDuration", RoundTo2(value), "chatFadeOutDuration")
      end,
    },
    {
      name = "Slide in duration",
      desc = "Seconds a new message takes to slide up. 0 turns the animation off",
      kind = LEM.SettingType.Slider,
      default = defaults.chatSlideInDuration,
      minValue = 0,
      maxValue = 2,
      valueStep = 0.05,
      formatter = RoundTo2,
      get = function () return profile().chatSlideInDuration end,
      set = function (_, value) Set("chatSlideInDuration", RoundTo2(value)) end,
    },
    {
      name = "Show on mouse over",
      desc = "Show faded messages again while the mouse is over the chat",
      kind = LEM.SettingType.Checkbox,
      default = defaults.chatShowOnMouseOver,
      get = function () return profile().chatShowOnMouseOver end,
      set = function (_, value) Set("chatShowOnMouseOver", value) end,
    },
    {
      name = "Short channel names",
      desc = "[1] instead of [1. General], [P] instead of [Party], and so on. Applies to new messages",
      kind = LEM.SettingType.Checkbox,
      default = defaults.shortChannelNames,
      get = function () return profile().shortChannelNames end,
      set = function (_, value) Set("shortChannelNames", value) end,
    },
    {
      name = "Edit box position",
      desc = "Where the box you type in appears",
      kind = LEM.SettingType.Dropdown,
      default = defaults.editBoxAnchor.position,
      values = {
        { text = "Above the chat", value = "ABOVE" },
        { text = "Below the chat", value = "BELOW" },
      },
      get = function () return profile().editBoxAnchor.position end,
      set = function (_, value)
        local anchor = profile().editBoxAnchor
        anchor.position = value
        anchor.yOfs = value == "ABOVE" and 5 or -5
        Set("editBoxAnchor", anchor, "editBoxAnchor")
      end,
    },
    {
      name = "Edit box opacity",
      desc = "Background opacity of the box you type in",
      kind = LEM.SettingType.Slider,
      default = defaults.editBoxBackgroundOpacity,
      minValue = 0,
      maxValue = 1,
      valueStep = 0.05,
      formatter = RoundTo2,
      get = function () return profile().editBoxBackgroundOpacity end,
      set = function (_, value)
        Set("editBoxBackgroundOpacity", RoundTo2(value), "editBoxBackgroundOpacity")
      end,
    },
  })

  -- The mover frame is normally hidden; show it (without its green
  -- "unlocked" background) while Edit Mode is open, so it can be selected.
  LEM:RegisterCallback("enter", function ()
    moverFrame.bg:SetAlpha(0)
    moverFrame:Show()
  end)

  LEM:RegisterCallback("exit", function ()
    moverFrame:Hide()
    moverFrame.bg:SetAlpha(1)
  end)
end
