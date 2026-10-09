local Core, Constants = unpack(select(2, ...))

local SaveFramePosition = Constants.ACTIONS.SaveFramePosition

local LOCK_MOVER = Constants.EVENTS.LOCK_MOVER
local UNLOCK_MOVER = Constants.EVENTS.UNLOCK_MOVER
local UPDATE_CONFIG = Constants.EVENTS.UPDATE_CONFIG

local MoverFrameMixin = {}

-- luacheck: push ignore 113
local C_XMLUtil = C_XMLUtil
local CreateFrame = CreateFrame
local Mixin = Mixin
-- luacheck: pop

function MoverFrameMixin:Init()
  local editBoxMargin = 35
  self:ClearAllPoints()
  self:SetPoint(
    Core.db.profile.positionAnchor.point,
    Core.db.profile.positionAnchor.xOfs,
    Core.db.profile.positionAnchor.yOfs
  )
  self:SetWidth(Core.db.profile.frameWidth)
  self:SetHeight(Core.db.profile.frameHeight + editBoxMargin)

  -- Highlight shown while the frame is unlocked. Uses the Edit Mode selection
  -- look (blue border with the name) when the game has it, otherwise the old
  -- green box.
  self.bg = self:CreateEditModeHighlight() or self:CreateGreenHighlight()

  self:Hide()

  self:RegisterForDrag("LeftButton")
  self:SetScript("OnDragStart", self.StartMoving)
  self:SetScript("OnDragStop", self.StopMovingOrSizing)

  if self.subscriptions == nil then
    self.subscriptions = {
      Core:Subscribe(LOCK_MOVER, function ()
        self:Hide()
        self:EnableMouse(false)
        self:SetMovable(false)

        local point, _, _, xOfs, yOfs = self:GetPoint(1)
        local position = {
          point = point,
          xOfs = xOfs,
          yOfs = yOfs
        }

        Core:Dispatch(SaveFramePosition(position))
      end),
      Core:Subscribe(UNLOCK_MOVER, function ()
        self.bg:SetAlpha(1)
        self.bg:Show()
        if self.bg.ShowSelected then
          pcall(self.bg.ShowSelected, self.bg, true)
        end
        self:Show()
        self:EnableMouse(true)
        self:SetMovable(true)
      end),
      Core:Subscribe(UPDATE_CONFIG, function (key)
        if (key == "frameWidth") then
          self:SetWidth(Core.db.profile.frameWidth)
        end

        if (key == "frameHeight") then
          self:SetHeight(Core.db.profile.frameHeight + editBoxMargin)
        end

        if key == "framePosition" then
          self:ClearAllPoints()
          self:SetPoint(
            Core.db.profile.positionAnchor.point,
            Core.db.profile.positionAnchor.xOfs,
            Core.db.profile.positionAnchor.yOfs
          )
        end
      end),
    }
  end
end

function MoverFrameMixin:CreateEditModeHighlight()
  if not (C_XMLUtil and C_XMLUtil.GetTemplateInfo and C_XMLUtil.GetTemplateInfo("EditModeSystemSelectionTemplate")) then
    return nil
  end

  local ok, highlight = pcall(CreateFrame, "Frame", nil, self, "EditModeSystemSelectionTemplate")
  if not ok or not highlight then return nil end

  -- Only the look is wanted: the mover frame itself handles dragging
  highlight.system = { GetSystemName = function () return "Glass Forever" end }
  highlight:SetScript("OnMouseDown", nil)
  highlight:SetScript("OnMouseUp", nil)
  highlight:SetScript("OnDragStart", nil)
  highlight:SetScript("OnDragStop", nil)
  highlight:EnableMouse(false)
  highlight:SetAllPoints()

  if not pcall(highlight.ShowSelected, highlight, true) then
    pcall(highlight.ShowHighlighted, highlight)
  end

  return highlight
end

function MoverFrameMixin:CreateGreenHighlight()
  local bg = self:CreateTexture(nil, "BACKGROUND")
  bg:SetColorTexture(0, 1, 0, 0.5)
  bg:SetAllPoints()
  return bg
end

Core.Components.CreateMoverFrame = function (name, parent)
  local frame = CreateFrame("Frame", name, parent)
  local object = Mixin(frame, MoverFrameMixin)
  object:Init()
  return object
end
