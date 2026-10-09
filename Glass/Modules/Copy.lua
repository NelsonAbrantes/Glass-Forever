local Core, Constants = unpack(select(2, ...))
local Copy = Core:GetModule("Copy")

-- luacheck: push ignore 113
local CreateFrame = CreateFrame
local UIParent = UIParent
-- luacheck: pop

local OpenCopy = Constants.ACTIONS.OpenCopy

local OPEN_COPY = Constants.EVENTS.OPEN_COPY

----
-- Copy Module
--
-- Lets players copy text out of the chat: a "Copy chat text" option in the
-- tab right-click menu, and clickable web links (see TextProcessing and
-- Hyperlinks). Both open a window with the text selected, ready for Ctrl+C.

-- Turns a chat line into plain text: no colors, icons or link codes
local function PlainText(text)
  if text == nil then return nil end
  if issecretvalue and issecretvalue(text) then return nil end

  text = text:gsub("|Hglassurl:.-|h%[(.-)%]|h", "%1") -- our web links, without brackets
  text = text:gsub("|H.-|h(.-)|h", "%1")
  text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
  text = text:gsub("|cn.-:", "")
  text = text:gsub("|r", "")
  text = text:gsub("|T.-|t", "")
  text = text:gsub("|A.-|a", "")
  text = text:gsub("||", "|")
  return text
end

-- Window built with the game's own panel template, so it matches the
-- current UI (bronze border) instead of the old Classic dialog look.
local window

local function CreateWindow()
  local frame = CreateFrame("Frame", "GlassCopyFrame", UIParent, "DefaultPanelFlatTemplate")
  frame:SetSize(600, 400)
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

  -- Close with the Escape key, like other game windows
  table.insert(_G.UISpecialFrames, "GlassCopyFrame")

  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetPoint("TOPLEFT", 7, -3)
  frame.bg:SetPoint("BOTTOMRIGHT", -3, 3)
  frame.bg:SetColorTexture(0.08, 0.08, 0.08, 1)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetFrameLevel((frame.TitleContainer or frame):GetFrameLevel() + 10)
  close:SetPoint("TOPRIGHT")

  local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 16, 10)
  hint:SetText("Ctrl+C to copy")

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -32)
  scroll:SetPoint("BOTTOMRIGHT", -34, 28)

  local editBox = CreateFrame("EditBox", nil, scroll)
  editBox:SetMultiLine(true)
  editBox:SetAutoFocus(false)
  editBox:SetFontObject("ChatFontNormal")
  editBox:SetWidth(scroll:GetWidth())
  editBox:SetScript("OnEscapePressed", function () frame:Hide() end)
  -- Keep the cursor in view while selecting long text
  if _G.ScrollingEdit_OnCursorChanged and _G.ScrollingEdit_OnUpdate then
    editBox:SetScript("OnCursorChanged", _G.ScrollingEdit_OnCursorChanged)
    editBox:SetScript("OnUpdate", function (self, elapsed)
      _G.ScrollingEdit_OnUpdate(self, elapsed, scroll)
    end)
  end
  scroll:SetScrollChild(editBox)
  scroll:SetScript("OnSizeChanged", function (_, width) editBox:SetWidth(width) end)

  frame.editBox = editBox
  return frame
end

local function ShowWindow(title, text, height)
  window = window or CreateWindow()
  window:SetTitle(title)
  window:SetHeight(height)
  window.editBox:SetText(text)
  window:Show()
  window.editBox:SetFocus()
  window.editBox:HighlightText()
end

function Copy:OnEnable()
  Core:Subscribe(OPEN_COPY, function (payload)
    ShowWindow(payload.title, payload.text, payload.height or 400)
  end)

  -- "Copy chat text" in the tab right-click menu
  _G.Menu.ModifyMenu("MENU_FCF_TAB", function (owner, rootDescription)
    local smf = owner and owner.slidingMessageFrame
    if not smf or not smf.state or smf.state.isCombatLog then return end

    rootDescription:CreateButton("Copy chat text", function ()
      local lines = {}
      for _, message in ipairs(smf.state.messages) do
        local text = message.text and PlainText(message.text:GetText())
        table.insert(lines, text or "(hidden message)")
      end

      Core:Dispatch(OpenCopy({
        title = "Glass Forever: Copy chat text",
        text = table.concat(lines, "\n"),
      }))
    end)
  end)
end
