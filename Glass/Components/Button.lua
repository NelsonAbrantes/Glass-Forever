local Core = unpack(select(2, ...))

-- luacheck: push ignore 113
local C_XMLUtil = C_XMLUtil
local CreateFrame = CreateFrame
-- luacheck: pop

-- Button templates from the current game UI (red with a gold border), from
-- the best fit to the least. The last one is the old Classic button, used only
-- if the game has none of the others.
local TEMPLATES = {
  { name = "SharedButtonSmallTemplate", scale = 1 },
  { name = "SharedButtonTemplate", scale = 1 },
  { name = "SharedButtonLargeTemplate", scale = 0.7 },
  { name = "UIPanelButtonTemplate", scale = 1 },
}

local chosen

local function ChooseTemplate()
  if chosen then return chosen end
  for _, template in ipairs(TEMPLATES) do
    if not C_XMLUtil or not C_XMLUtil.GetTemplateInfo or C_XMLUtil.GetTemplateInfo(template.name) then
      chosen = template
      return chosen
    end
  end
  chosen = TEMPLATES[#TEMPLATES]
  return chosen
end

---
-- Creates a button in the current game style. Its width follows the text.
Core.Components.CreateButton = function (parent)
  local template = ChooseTemplate()
  local button = CreateFrame("Button", nil, parent, template.name)
  button:SetScale(template.scale)

  local function Resize()
    if _G.DynamicResizeButton_Resize and button.padding then
      _G.DynamicResizeButton_Resize(button)
    else
      button:SetWidth(button:GetTextWidth() + 40)
    end
  end

  -- Resize to the text every time it changes
  hooksecurefunc(button, "SetText", Resize)

  if template.name == "UIPanelButtonTemplate" then
    button:SetHeight(22)
  else
    button.padding = 40
  end

  return button
end
