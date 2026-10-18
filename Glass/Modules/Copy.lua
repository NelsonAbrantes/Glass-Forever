local Core, Constants, Utils = unpack(select(2, ...))
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

local PlainText = Utils.PlainText

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

---
-- Search (a tab's right-click menu, "Search messages"): a window with a box
-- to type in; the tab's messages that contain it show below, newest first,
-- in their colors. It looks through the messages the tab still holds (its
-- last 128).
local SEARCH_MAX = 100
local searchWindow

local function SearchResults(smf, query)
  local lines, found = {}, 0
  query = query:lower()
  local messages = smf.state and smf.state.messages or {}
  for i = #messages, 1, -1 do
    local message = messages[i]
    local raw = message.raw and message.raw.text
    if type(raw) == "string" and not (issecretvalue and issecretvalue(raw)) then
      local plain = PlainText(raw)
      if plain and plain:lower():find(query, 1, true) then
        found = found + 1
        if found <= SEARCH_MAX then
          local r, g, b = message.raw.r or 1, message.raw.g or 1, message.raw.b or 1
          local shown = message.text and message.text:GetText() or plain
          table.insert(lines, string.format("|cff%02x%02x%02x%s|r",
            math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), shown))
        end
      end
    end
  end
  return lines, found
end

local function CreateSearchWindow()
  local frame = CreateFrame("Frame", "GlassSearchFrame", UIParent, "DefaultPanelFlatTemplate")
  frame:SetSize(560, 420)
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
  table.insert(_G.UISpecialFrames, "GlassSearchFrame")

  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetPoint("TOPLEFT", 7, -3)
  frame.bg:SetPoint("BOTTOMRIGHT", -3, 3)
  frame.bg:SetColorTexture(0.08, 0.08, 0.08, 1)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetFrameLevel((frame.TitleContainer or frame):GetFrameLevel() + 10)
  close:SetPoint("TOPRIGHT")

  local input = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  input:SetPoint("TOPLEFT", 22, -34)
  input:SetPoint("TOPRIGHT", -120, -34)
  input:SetHeight(22)
  input:SetAutoFocus(false)
  input:SetScript("OnEscapePressed", function () frame:Hide() end)
  input:SetScript("OnEnterPressed", function (self) self:ClearFocus() end)

  local count = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  count:SetPoint("LEFT", input, "RIGHT", 12, 0)

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 16, -64)
  scroll:SetPoint("BOTTOMRIGHT", -34, 14)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  local results = content:CreateFontString(nil, "ARTWORK", "ChatFontNormal")
  results:SetPoint("TOPLEFT")
  results:SetJustifyH("LEFT")
  results:SetJustifyV("TOP")
  results:SetSpacing(3)

  local function Layout()
    local width = scroll:GetWidth()
    results:SetWidth(width)
    content:SetWidth(width)
    content:SetHeight(math.max(1, results:GetStringHeight()))
  end
  scroll:SetScript("OnSizeChanged", Layout)

  function frame:Search()
    local query = input:GetText() or ""
    if query == "" then
      results:SetText("")
      count:SetText("Type to search")
    else
      local lines, found = SearchResults(self.smf, query)
      results:SetText(table.concat(lines, "\n"))
      if found == 0 then
        count:SetText("No messages")
      elseif found > SEARCH_MAX then
        count:SetText(found.." messages (newest "..SEARCH_MAX..")")
      else
        count:SetText(found..(found == 1 and " message" or " messages"))
      end
    end
    Layout()
    scroll:SetVerticalScroll(0)
  end
  input:SetScript("OnTextChanged", function () frame:Search() end)

  frame.input = input
  return frame
end

local function OpenSearch(smf, name)
  searchWindow = searchWindow or CreateSearchWindow()
  searchWindow.smf = smf
  searchWindow:SetTitle("Glass Forever: Search "..(name or "messages"))
  searchWindow:Show()
  searchWindow:Search()
  searchWindow.input:SetFocus()
end

function Copy:OnEnable()
  Core:Subscribe(OPEN_COPY, function (payload)
    ShowWindow(payload.title, payload.text, payload.height or 400)
  end)

  -- "Copy chat text" in the tab right-click menu
  _G.Menu.ModifyMenu("MENU_FCF_TAB", function (owner, rootDescription)
    local smf = owner and owner.slidingMessageFrame
    if not smf or not smf.state or smf.state.isCombatLog then return end

    rootDescription:CreateButton("Search messages", function ()
      OpenSearch(smf, owner.GetText and owner:GetText() or nil)
    end)

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
