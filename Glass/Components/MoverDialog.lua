local Core, Constants = unpack(select(2, ...))

local LockMover = Constants.ACTIONS.LockMover

local LOCK_MOVER = Constants.EVENTS.LOCK_MOVER
local UNLOCK_MOVER = Constants.EVENTS.UNLOCK_MOVER

local MoverDialogMixin = {}

-- luacheck: push ignore 113
local CreateFrame = CreateFrame
local Mixin = Mixin
local PlaySound = PlaySound
local SOUNDKIT = SOUNDKIT
-- luacheck: pop

function MoverDialogMixin:Init()
  self:SetFrameStrata("DIALOG")
  self:SetToplevel(true)
  self:EnableMouse(false)
  self:SetMovable(false)
  self:SetClampedToScreen(true)
  self:SetWidth(360)
  self:SetHeight(120)
  self:SetPoint("TOP", 0, -50)
  self:Hide()

  self:SetScript("OnShow", function() PlaySound(SOUNDKIT.IG_MAINMENU_OPTION) end)
  self:SetScript("OnHide", function() PlaySound(SOUNDKIT.GS_TITLE_OPTION_EXIT) end)

  -- Game panel look (bronze border), same as the Copy window
  if self.SetTitle then
    self:SetTitle("Glass")
  end

  self.bg = self:CreateTexture(nil, "BACKGROUND")
  self.bg:SetPoint("TOPLEFT", 7, -3)
  self.bg:SetPoint("BOTTOMRIGHT", -3, 3)
  self.bg:SetColorTexture(0.08, 0.08, 0.08, 1)

  self.desc = self:CreateFontString("ARTWORK")
  self.desc:SetFontObject("GameFontHighlight")
  self.desc:SetJustifyV("TOP")
  self.desc:SetJustifyH("LEFT")
  self.desc:SetPoint("TOPLEFT", 18, -34)
  self.desc:SetPoint("BOTTOMRIGHT", -18, 48)
  self.desc:SetText("Chat frame unlocked. You can now drag the chat frame to reposition it.")

  self.lockButton = Core.Components.CreateButton(self)
  self.lockButton:SetText("Lock")
  self.lockButton:SetScript("OnClick", function()
    Core:Dispatch(LockMover())
  end)
  self.lockButton:SetPoint("BOTTOMRIGHT", -14, 14)

  Core:Subscribe(LOCK_MOVER, function ()
    self:Hide()
  end)

  Core:Subscribe(UNLOCK_MOVER, function ()
    self:Show()
  end)
end

Core.Components.CreateMoverDialog = function (name, parent)
  local frame = CreateFrame("Frame", name, parent, "DefaultPanelFlatTemplate")
  local object = Mixin(frame, MoverDialogMixin)
  object:Init()
  return object
end
