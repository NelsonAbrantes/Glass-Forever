local Core, Constants, Utils = unpack(select(2, ...))
local SpamFilter = Core:GetModule("SpamFilter")

-- luacheck: push ignore 113
local CreateFrame = CreateFrame
local UIParent = UIParent
-- luacheck: pop

local OPEN_SPAM_WORDS = Constants.EVENTS.OPEN_SPAM_WORDS

----
-- SpamFilter Module
--
-- Hides chat messages that contain blocked words or phrases (Options >
-- Messages > Spam filter), e.g. gold sellers. Only Glass stops showing them:
-- the game still receives them, so nothing else is affected. Messages the
-- game marks as secret can't be read, so they're always shown.

-- Lowercase copies of the blocked words, rebuilt when the list changes
local blocked = {}

local function Rebuild()
  blocked = {}
  for _, word in ipairs(Core.db.profile.spamWords or {}) do
    if type(word) == "string" and word ~= "" then
      table.insert(blocked, word:lower())
    end
  end
end

---
-- True if Glass should hide this message
function SpamFilter:IsSpam(text)
  if not Core.db.profile.spamFilter or #blocked == 0 then return false end
  local plain = Utils.PlainText(text)
  if not plain then return false end
  plain = plain:lower()
  for _, word in ipairs(blocked) do
    if plain:find(word, 1, true) then
      return true
    end
  end
  return false
end

-- Window to edit the list, one word or phrase per line
local window

local function CreateWindow()
  local frame = CreateFrame("Frame", "GlassSpamWordsFrame", UIParent, "DefaultPanelFlatTemplate")
  frame:SetSize(420, 360)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:Hide()
  if frame.SetTitle then
    frame:SetTitle("Glass Forever: Blocked words")
  end

  -- Close with the Escape key, like other game windows
  table.insert(_G.UISpecialFrames, "GlassSpamWordsFrame")

  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetPoint("TOPLEFT", 7, -3)
  frame.bg:SetPoint("BOTTOMRIGHT", -3, 3)
  frame.bg:SetColorTexture(0.08, 0.08, 0.08, 1)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetFrameLevel((frame.TitleContainer or frame):GetFrameLevel() + 10)
  close:SetPoint("TOPRIGHT")

  local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  hint:SetPoint("TOPLEFT", 16, -32)
  hint:SetPoint("TOPRIGHT", -16, -32)
  hint:SetJustifyH("LEFT")
  hint:SetText("One word or phrase per line. Messages that contain any of them are hidden. Upper and lower case don't matter.")

  -- Dark box around the text, so it's clear where to type
  local box = CreateFrame("Frame", nil, frame)
  box:SetPoint("TOPLEFT", 14, -64)
  box:SetPoint("BOTTOMRIGHT", -14, 48)
  local boxBg = box:CreateTexture(nil, "BACKGROUND")
  boxBg:SetAllPoints()
  boxBg:SetColorTexture(0, 0, 0, 0.5)

  local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 6, -6)
  scroll:SetPoint("BOTTOMRIGHT", -26, 6)

  local editBox = CreateFrame("EditBox", nil, scroll)
  editBox:SetMultiLine(true)
  editBox:SetAutoFocus(false)
  editBox:SetFontObject("ChatFontNormal")
  editBox:SetWidth(scroll:GetWidth())
  editBox:SetScript("OnEscapePressed", function () frame:Hide() end)
  if _G.ScrollingEdit_OnCursorChanged and _G.ScrollingEdit_OnUpdate then
    editBox:SetScript("OnCursorChanged", _G.ScrollingEdit_OnCursorChanged)
    editBox:SetScript("OnUpdate", function (self, elapsed)
      _G.ScrollingEdit_OnUpdate(self, elapsed, scroll)
    end)
  end
  scroll:SetScrollChild(editBox)
  scroll:SetScript("OnSizeChanged", function (_, width) editBox:SetWidth(width) end)
  -- Clicking anywhere in the box starts typing
  box:EnableMouse(true)
  box:SetScript("OnMouseDown", function () editBox:SetFocus() end)

  local save = Core.Components.CreateButton(frame)
  save:SetText("Save")
  save:SetPoint("BOTTOMRIGHT", -14, 14)
  save:SetScript("OnClick", function ()
    local words = {}
    for line in (editBox:GetText() .. "\n"):gmatch("(.-)\n") do
      line = line:match("^%s*(.-)%s*$")
      if line ~= "" then
        table.insert(words, line)
      end
    end
    Core.db.profile.spamWords = words
    Rebuild()
    frame:Hide()
  end)

  local cancel = Core.Components.CreateButton(frame)
  cancel:SetText("Cancel")
  cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)
  cancel:SetScript("OnClick", function () frame:Hide() end)

  frame.editBox = editBox
  return frame
end

local function ShowWindow()
  window = window or CreateWindow()
  window.editBox:SetText(table.concat(Core.db.profile.spamWords or {}, "\n"))
  window:Show()
  window.editBox:SetFocus()
end

function SpamFilter:OnEnable()
  Rebuild()

  Core:Subscribe(OPEN_SPAM_WORDS, ShowWindow)

  -- A different profile has its own list
  Core.db.RegisterCallback(self, "OnProfileChanged", Rebuild)
  Core.db.RegisterCallback(self, "OnProfileCopied", Rebuild)
  Core.db.RegisterCallback(self, "OnProfileReset", Rebuild)
end
