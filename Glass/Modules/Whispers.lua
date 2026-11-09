local Core, Constants = unpack(select(2, ...))
local Whispers = Core:GetModule("Whispers")

local LSM = Core.Libs.LSM
local UPDATE_CONFIG = Constants.EVENTS.UPDATE_CONFIG

-- luacheck: push ignore 113
local Ambiguate = Ambiguate
local C_BattleNet = C_BattleNet
local C_ChatInfo = C_ChatInfo
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local GetPlayerInfoByGUID = GetPlayerInfoByGUID
local GetTime = GetTime
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local UIParent = UIParent
local UnitName = UnitName
local date = date
local time = time
-- luacheck: pop

local GetCVar = C_CVar and C_CVar.GetCVar or _G.GetCVar
local SetCVar = C_CVar and C_CVar.SetCVar or _G.SetCVar

local ASSETS = "Interface\\Addons\\Glass\\Glass\\Assets\\Buttons\\"
local TAB_ASSETS = "Interface\\AddOns\\Glass\\Glass\\Assets\\Tabs\\"

local MAX_LINES = 50        -- messages kept per conversation
local MAX_CONVERSATIONS = 10 -- in the list at once; the oldest goes
local TITLE_HEIGHT = 22
local INPUT_HEIGHT = 22
local FADE_CHECK = 0.1      -- seconds between checks of a window's fade
local FADED_ALPHA = 0.35    -- an idle window

local CVARS = { "whisperMode", "bnWhisperMode" }

local EVENTS = {
  CHAT_MSG_WHISPER = { bn = false, out = false },
  CHAT_MSG_WHISPER_INFORM = { bn = false, out = true },
  CHAT_MSG_BN_WHISPER = { bn = true, out = false },
  CHAT_MSG_BN_WHISPER_INFORM = { bn = true, out = true },
}

----
-- Whispers Module
--
-- Whispers in their own small windows instead of chat tabs (Options >
-- Messages > Whisper windows, on by default). An envelope at the right end
-- of the tab bar counts the people with something new; a click lists the
-- conversations, and a click on one opens it, with a box to answer in. The
-- windows are Glass' own frames, not the game's chat windows: whisper tabs
-- opened by an addon were "tainted" and made the game's chat code fail.
--
-- The game is set to show whispers inline (Options > Social > New Whispers),
-- so it opens no tabs, and Glass leaves them out of the chat. Turned off, the
-- game option goes back to what it was and whispers stay in the chat.
--
-- In dungeons the game hides the text of messages from addons ("secret"): it
-- still shows in the window, but also stays in the chat, and isn't saved.

local conversations = {} -- key -> conversation
local order = {}         -- keys, oldest first
local whisperIDs         -- ChatTypeInfo ids of the whisper lines
local windowCount = 0
local enabled = false

local function Profile() return Core.db.profile end

-- The windows in the chat's look (Options > Whispers > Look)
local function ChatLook()
  return Profile().whisperLook == "chat"
end

-- An option that can be "auto": then what suits the look, the phone chat's
-- or the chat's
local function Choice(key, boxes, chat)
  local value = Profile()[key]
  if value == nil or value == "auto" then
    return ChatLook() and chat or boxes
  end
  return value
end

local function Readable(value)
  return not (issecretvalue and issecretvalue(value))
end

function Whispers:Active()
  return enabled
end

----
-- Lines the chat leaves out: the whisper ones (their chat type id), when the
-- text can be read (secret text stays in the chat too, as it can't be saved)
function Whispers:HidesLine(text, id)
  if not enabled or not Readable(id) or id == nil or not Readable(text) then return false end
  if not whisperIDs then
    whisperIDs = {}
    local info = _G.ChatTypeInfo
    for _, chatType in ipairs({ "WHISPER", "WHISPER_INFORM", "BN_WHISPER", "BN_WHISPER_INFORM" }) do
      if info and info[chatType] and info[chatType].id then
        whisperIDs[info[chatType].id] = true
      end
    end
  end
  return whisperIDs[id] == true
end

----
-- Looks

-- The windows' text (Options > Whispers): font, size and outline, each
-- "same as the messages" when not chosen
local function Font()
  local profile = Profile()
  local name = profile.whisperFont
  if not name or name == "" then name = profile.font end
  local file = LSM:Fetch("font", name)
  local size = profile.whisperFontSize
  if not size or size == 0 then size = profile.messageFontSize or 12 end
  local flags = profile.whisperFontFlags
  if flags == nil or flags == "same" then flags = profile.fontFlags or "" end
  return file, size, flags
end

local function WindowOpacity()
  return Profile().whisperWindowOpacity or 0.75
end

local function Gold()
  return Constants.COLORS.apache
end

local function WhisperColor(bn, out)
  local info = _G.ChatTypeInfo
  local chatType = (bn and "BN_WHISPER" or "WHISPER")..(out and "_INFORM" or "")
  local color = info and info[chatType]
  if color and color.r then return color.r, color.g, color.b end
  return 1, 0.5, 1
end

-- The names' color, in the envelope's list and the windows (Options): gold,
-- their class, or the whisper color. For your own name (outgoing lines),
-- class is your class and gold a quiet gray.
local function PersonColor(conversation, outgoing)
  local choice = Choice("whisperNameColor", "gold", "class")
  if choice == "class" then
    local class = conversation.class
    if outgoing then class = select(2, _G.UnitClass("player")) end
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if conversation.bn and not outgoing then
      local info = _G.ChatTypeInfo and _G.ChatTypeInfo.BN_WHISPER
      if info and info.r then return info.r, info.g, info.b end
    end
    if color then return color.r, color.g, color.b end
  elseif choice == "whisper" then
    return WhisperColor(conversation.bn, outgoing)
  end
  if outgoing then return 0.6, 0.6, 0.6 end
  local gold = Gold()
  return gold.r, gold.g, gold.b
end

local function Hex(r, g, b)
  return string.format("ff%02x%02x%02x", r * 255, g * 255, b * 255)
end


-- A small icon button in the Glass style (icon in gold, dark outline)
local function IconButton(parent, icon, size)
  local button = CreateFrame("Button", nil, parent)
  button:SetSize(size + 4, size + 4)
  button.outline = button:CreateTexture(nil, "ARTWORK")
  button.outline:SetTexture(ASSETS..icon.."Outline")
  button.outline:SetSize(size, size)
  button.outline:SetPoint("CENTER")
  button.outline:SetVertexColor(0, 0, 0, 0.85)
  button.icon = button:CreateTexture(nil, "OVERLAY")
  button.icon:SetTexture(ASSETS..icon)
  button.icon:SetSize(size, size)
  button.icon:SetPoint("CENTER")
  local gold = Gold()
  local function Color(hover)
    local k = hover and 0.4 or 0
    button.icon:SetVertexColor(gold.r + (1 - gold.r) * k, gold.g + (1 - gold.g) * k, gold.b + (1 - gold.b) * k, hover and 1 or 0.8)
  end
  Color(false)
  button:SetScript("OnEnter", function () Color(true) end)
  button:SetScript("OnLeave", function () Color(false) end)
  return button
end

----
-- Saved conversations (per character): name, target, Battle.net tag and the
-- last lines, { time, outgoing, text }

local function Saved()
  Core.db.char.whisperConversations = Core.db.char.whisperConversations or {}
  return Core.db.char.whisperConversations
end

-- A Battle.net friend's current account id from their BattleTag (the id and
-- the shown name change every session)
local function FindBNetFriend(tag)
  if not (tag and C_BattleNet and C_BattleNet.GetFriendAccountInfo) then return nil end
  local count = _G.BNGetNumFriends and _G.BNGetNumFriends() or 0
  for i = 1, count do
    local info = C_BattleNet.GetFriendAccountInfo(i)
    if info and info.battleTag == tag then return info end
  end
end

local function BNetTag(bnID)
  if not (bnID and C_BattleNet and C_BattleNet.GetAccountInfoByID) then return nil end
  local info = C_BattleNet.GetAccountInfoByID(bnID)
  return info and Readable(info.battleTag) and info.battleTag or nil
end

-- The name to whisper: as the game gave it, without your own realm (this
-- server doesn't take "Name-YourRealm": "No player named ...")
local function WhisperTarget(name)
  local realm = _G.GetNormalizedRealmName and _G.GetNormalizedRealmName()
  if realm and realm ~= "" then
    local suffix = "-"..realm
    if name:sub(-#suffix) == suffix then return name:sub(1, -#suffix - 1) end
  end
  return name
end

----
-- The messages of a window, like a phone chat: what they said on the left in
-- a dark box, what you said on the right in a box tinted with the whisper
-- color. The name on top of the first box of a run, the time small in the
-- box's corner. Newest at the bottom; the mouse wheel goes back.

local VIEW_MAX_LINES = 120   -- messages kept in a window
local BUBBLE_PART = 0.78     -- widest a box gets, as a part of the window
local PAD_X, PAD_Y = 7, 4    -- room inside a box
local GAP = 2                -- between boxes of the same person
local GROUP_GAP = 7          -- between one person's boxes and the other's
local TIME_GAP = 8           -- between the text and the time
local SCROLL_STEP = 30
local BUBBLE_TEXTURE = ASSETS.."whisperBubble"

local ViewMixin = {}

-- A number the game may hide in dungeons (from secret text): nil then
local function Number(value)
  if value == nil or not Readable(value) then return nil end
  return value
end

local function Width(fontString)
  local width = fontString.GetUnboundedStringWidth and fontString:GetUnboundedStringWidth() or fontString:GetStringWidth()
  return Number(width)
end

local function SetFonts(view, line)
  local font = view.font
  if not font then return end
  line.text:SetFont(font[1], font[2], font[3])
  line.name:SetFont(font[1], font[2], font[3])
  line.time:SetFont(font[1], math.max(8, font[2] - 3), font[3])
end

function ViewMixin:SetFont(file, size, flags)
  self.font = { file, size, flags }
  for _, line in ipairs(self.lines) do SetFonts(self, line) end
  for _, line in ipairs(self.spare) do SetFonts(self, line) end
  self:Layout()
end

-- The boxes' colors (Options > Whispers > Phone chat): the whisper color, or
-- one of these, darkened so the text reads on it
local BUBBLE_COLORS = {
  dark = { r = 0.16, g = 0.16, b = 0.16 },
  black = { r = 0, g = 0, b = 0 },
  gold = { r = 1, g = 0.78, b = 0.3, dim = true },
  blue = { r = 0.3, g = 0.55, b = 1, dim = true },
  green = { r = 0.3, g = 0.85, b = 0.4, dim = true },
  purple = { r = 0.7, g = 0.4, b = 1, dim = true },
  red = { r = 1, g = 0.3, b = 0.3, dim = true },
}
local BUBBLE_DIM = 0.3

-- side: "left" (theirs) or "right" (yours)
local function BubbleColor(side)
  local profile = Profile()
  local choice
  if side == "right" then
    choice = profile.whisperBubbleYours or "whisper"
  else
    choice = profile.whisperBubbleTheirs or "dark"
  end
  if choice == "whisper" then
    local r, g, b = WhisperColor(false, side == "right")
    return r * BUBBLE_DIM, g * BUBBLE_DIM, b * BUBBLE_DIM
  end
  local color = BUBBLE_COLORS[choice] or BUBBLE_COLORS.dark
  local k = color.dim and BUBBLE_DIM or 1
  return color.r * k, color.g * k, color.b * k
end

-- Rounded corners that keep their size whatever the box's size, or square
local function BubbleShape(line)
  local square = Profile().whisperBubbleShape == "square"
  if line.square == square then return end
  line.square = square
  if square then
    line.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    if line.bg.ClearTextureSlice then line.bg:ClearTextureSlice() end
  else
    line.bg:SetTexture(BUBBLE_TEXTURE)
    if line.bg.SetTextureSliceMargins then
      line.bg:SetTextureSliceMargins(8, 8, 8, 8)
      if line.bg.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
        line.bg:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
      end
    end
  end
end

-- Links whose tooltip Glass opens itself (OnHyperlinkClick below)
local TOOLTIP_LINKS = {
  item = true, spell = true, enchant = true, achievement = true, quest = true,
  currency = true, talent = true,
}

local function NewLine(view)
  local line = CreateFrame("Frame", nil, view.content)
  line.bg = line:CreateTexture(nil, "BACKGROUND")
  line.bg:SetAllPoints()
  BubbleShape(line)
  line.name = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  line.name:SetPoint("TOPLEFT", PAD_X, -PAD_Y)
  line.name:SetJustifyH("LEFT")
  line.name:SetWordWrap(false)
  line.text = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  line.text:SetJustifyH("LEFT")
  line.text:SetJustifyV("TOP")
  line.text:SetWordWrap(true)
  line.time = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  line.time:SetPoint("BOTTOMRIGHT", -PAD_X, PAD_Y - 1)
  line.time:SetTextColor(0.6, 0.6, 0.6)
  SetFonts(view, line)
  -- Item and player links in the messages
  line:SetHyperlinksEnabled(true)
  line:SetScript("OnHyperlinkClick", function (_, link, text, button)
    -- A web link: the copy window (the game can't open it)
    local url = Readable(link) and type(link) == "string" and link:match("^glassurl:(.+)$")
    if url then
      Core:Dispatch(Constants.ACTIONS.OpenCopy({ title = "Glass Forever: Copy link", text = url, height = 140 }))
      return
    end
    -- Items, spells, recipes, etc: their tooltip opened here (shift-click:
    -- into the chat's edit box). The game's own handling (SetItemRef), called
    -- by an addon, runs into functions only the game may call and was blocked.
    local kind = Readable(link) and type(link) == "string" and link:match("^(%a+):")
    if kind and TOOLTIP_LINKS[kind] then
      if _G.IsModifiedClick() and _G.HandleModifiedItemClick then
        pcall(_G.HandleModifiedItemClick, text)
        return
      end
      local tooltip = _G.ItemRefTooltip
      if tooltip:IsShown() and tooltip.glassLink == link then
        tooltip:Hide() -- (a second click closes it, like in the chat)
        return
      end
      tooltip.glassLink = link
      tooltip:SetOwner(_G.UIParent, "ANCHOR_PRESERVE")
      if pcall(tooltip.SetHyperlink, tooltip, link) then tooltip:Show() else tooltip:Hide() end
      return
    end
    pcall(_G.SetItemRef, link, text, button)
  end)
  line:SetScript("OnHyperlinkEnter", function (self, link)
    if not Readable(link) then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    if not pcall(GameTooltip.SetHyperlink, GameTooltip, link) then GameTooltip:Hide() end
  end)
  line:SetScript("OnHyperlinkLeave", function () GameTooltip:Hide() end)
  return line
end

-- message: { text, r, g, b, side = "left" (theirs), "right" (yours) or
-- "center" (a note), name, nameR, nameG, nameB, time }
function ViewMixin:AddMessage(message)
  local line
  if #self.lines >= VIEW_MAX_LINES then
    line = table.remove(self.lines, 1)
  else
    line = table.remove(self.spare) or NewLine(self)
  end
  local side = message.side or "left"
  line.side = side
  -- The first box of a run of the same person's: their name on top, and a
  -- little more room above it
  local previous = self.lines[#self.lines]
  line.first = not previous or previous.side ~= side
  line.text:SetText(message.text)
  line.text:SetTextColor(message.r or 1, message.g or 1, message.b or 1)
  local showName = line.first and side == "left" and message.name ~= nil
  line.name:SetText(showName and message.name or "")
  line.name:SetShown(showName)
  if showName then line.name:SetTextColor(message.nameR or 1, message.nameG or 1, message.nameB or 1) end
  line.time:SetText(message.time or "")
  line.time:SetShown(message.time ~= nil and side ~= "center")

  -- "Same as the chat" look: the chat's fading background instead of a box
  -- (drawn in Layout, it depends on the width)
  local chatLook = side == "chat"
  line.bg:SetShown(not chatLook)
  if line.leftBg and not chatLook then
    line.leftBg:Hide()
    line.rightBg:Hide()
    line.centerBg:Hide()
  end

  local dark = Constants.COLORS.codGray
  if chatLook then
    if not line.SetGradientBackground then Mixin(line, Core.Components.GradientBackgroundMixin) end
  else
    BubbleShape(line)
    if side == "center" then
      line.bg:SetVertexColor(dark.r, dark.g, dark.b, 0.7)
    else
      local r, g, b = BubbleColor(side)
      line.bg:SetVertexColor(r, g, b, Profile().whisperBubbleOpacity or 0.9)
    end
  end
  line:Show()
  table.insert(self.lines, line)
  self.scroll = 0 -- back to the newest
  self:Layout()
end

function ViewMixin:Clear()
  for _, line in ipairs(self.lines) do
    line:Hide()
    table.insert(self.spare, line)
  end
  wipe(self.lines)
  self.scroll = 0
  self:Layout()
end

-- Sizes each box to its text and stacks them up from the bottom
function ViewMixin:Layout()
  local viewWidth = Number(self:GetWidth()) or 300
  local viewHeight = Number(self:GetHeight()) or 150
  local maxBox = math.max(60, viewWidth * BUBBLE_PART)
  local size = self.font and self.font[2] or 12
  local y = 0
  for i = #self.lines, 1, -1 do
    local line = self.lines[i]
    if line.side == "chat" then
      y = y + self:LayoutChatLine(line, viewWidth, size, y)
    else
      y = y + self:LayoutBox(line, maxBox, size, y)
    end
  end
  self.total = y
  self.scroll = math.max(0, math.min(self.scroll or 0, y - viewHeight))
  self.content:ClearAllPoints()
  self.content:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 0, -self.scroll)
  self.content:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, -self.scroll)
  self.content:SetHeight(math.max(1, y))
end

-- A line in the chat's look: across the whole window, its background fading
-- out at the ends like the chat's messages. Returns the room it takes.
function ViewMixin:LayoutChatLine(line, viewWidth, size, y)
  local profile = Profile()
  local padX = Constants.TEXT_XPADDING
  local padY = math.floor(size * (profile.messageLinePadding or 0.25) + 0.5)
  local text = line.text
  text:SetJustifyH("LEFT")
  -- The chat's shadow and line spacing
  text:SetShadowColor(0, 0, 0, 1)
  text:SetShadowOffset(1, -1)
  text:SetSpacing(profile.messageLeading or 3)
  text:SetWidth(math.max(20, viewWidth - padX * 2))
  local textHeight = Number(text:GetStringHeight()) or size * 2.4
  local height = textHeight + padY * 2
  text:ClearAllPoints()
  text:SetPoint("TOPLEFT", padX, -padY)
  line:SetSize(viewWidth, height)
  line:ClearAllPoints()
  line:SetPoint("BOTTOMLEFT", self.content, "BOTTOMLEFT", 0, y)
  local left, right = 50, math.max(10, math.min(250, viewWidth - 50))
  if profile.messageBackgroundFull then left, right = 12, 12 end
  line:SetGradientBackground(left, right, Constants.COLORS.codGray, profile.chatBackgroundOpacity or 0.4)
  line.leftBg:Show()
  line.rightBg:Show()
  line.centerBg:Show()
  return height
end

-- A box (the phone chat look). Returns the room it takes.
function ViewMixin:LayoutBox(line, maxBox, size, y)
  do
    local text, name, time = line.text, line.name, line.time
    text:SetShadowOffset(0, 0)
    text:SetSpacing(0)
    local timeWidth = line.time:IsShown() and (Width(time) or 0) or 0
    local nameWidth = name:IsShown() and (Width(name) or 0) or 0
    local nameHeight = name:IsShown() and size + 2 or 0

    -- The text on one line with the time after it, if it fits; otherwise
    -- wrapped to the widest box, the time under its last line
    local maxText = maxBox - PAD_X * 2
    local textWidth = Width(text)
    local timeRoom = timeWidth > 0 and (timeWidth + TIME_GAP) or 0
    local oneLine = textWidth and (textWidth + timeRoom) <= maxText
    local inner
    if oneLine then
      text:SetWidth(textWidth + 1)
      inner = math.max(textWidth + timeRoom, nameWidth)
    else
      text:SetWidth(maxText)
      inner = maxText
    end
    inner = math.min(maxText, math.ceil(inner) + 1)
    -- (secret text: about two lines)
    local textHeight = Number(text:GetStringHeight()) or size * 2.4
    local height = PAD_Y * 2 + nameHeight + textHeight
    if not oneLine and timeWidth > 0 then height = height + size - 2 end

    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", PAD_X, -PAD_Y - nameHeight)
    line:SetSize(inner + PAD_X * 2, height)
    line:ClearAllPoints()
    if line.side == "right" then
      line:SetPoint("BOTTOMRIGHT", self.content, "BOTTOMRIGHT", 0, y)
    elseif line.side == "center" then
      line:SetPoint("BOTTOM", self.content, "BOTTOM", 0, y)
    else
      line:SetPoint("BOTTOMLEFT", self.content, "BOTTOMLEFT", 0, y)
    end
    return height + (line.first and GROUP_GAP or GAP)
  end
end

local function CreateView(parent)
  local view = CreateFrame("Frame", nil, parent)
  Mixin(view, ViewMixin)
  view.lines, view.spare, view.scroll = {}, {}, 0
  view:SetClipsChildren(true)
  view.content = CreateFrame("Frame", nil, view)
  view:EnableMouseWheel(true)
  view:SetScript("OnMouseWheel", function (self, delta)
    -- Up: older messages
    self.scroll = (self.scroll or 0) + delta * SCROLL_STEP
    self:Layout()
  end)
  -- (a new size: the boxes wrap again; only while it changes)
  view:SetScript("OnSizeChanged", function (self) self:Layout() end)
  return view
end

----
-- Window

local Show, Hide, Layout, Remove, ApplyBackground

local function UpdateFade(conversation, elapsed)
  local window = conversation.window
  window.sinceCheck = (window.sinceCheck or 0) + elapsed
  if window.sinceCheck < FADE_CHECK then
    if window.alpha ~= window.target then
      local step = elapsed / math.max(0.05, Profile().chatFadeOutDuration or 0.6)
      if window.target > window.alpha then
        window.alpha = math.min(window.target, window.alpha + step * 3)
      else
        window.alpha = math.max(window.target, window.alpha - step)
      end
      window:SetAlpha(window.alpha)
    end
    return
  end
  window.sinceCheck = 0
  local busy = window:IsMouseOver() or window.input:HasFocus()
    or GetTime() < (window.visibleUntil or 0)
  if busy then window.visibleUntil = math.max(window.visibleUntil or 0, GetTime() + 2) end
  window.target = (busy or Profile().messageFade == false) and 1 or FADED_ALPHA
end

local function SendWhisper(conversation, message)
  if conversation.bn then
    local info = FindBNetFriend(conversation.tag)
    local bnID = (info and info.bnetAccountID) or conversation.bnID
    if not bnID then return end
    if C_BattleNet and C_BattleNet.SendWhisper then
      pcall(C_BattleNet.SendWhisper, bnID, message)
    elseif _G.BNSendWhisper then
      pcall(_G.BNSendWhisper, bnID, message)
    end
  else
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or _G.SendChatMessage
    local ok, err = pcall(send, message, "WHISPER", nil, WhisperTarget(conversation.target))
    if not ok then print("|cffdfba69Glass Forever|r: the whisper couldn't be sent:", err) end
  end
end

local function SavePosition(window)
  local point, _, relativePoint, x, y = window:GetPoint(1)
  Core.db.profile.whisperWindow = {
    point = point, relativePoint = relativePoint, x = x, y = y,
    width = window:GetWidth(), height = window:GetHeight(),
  }
end

local function ApplyFonts(window)
  local file, size, flags = Font()
  if not file then return end
  window.title:SetFont(file, size, flags)
  window.messages:SetFont(file, size, flags)
  window.input:SetFont(file, size, flags)
  window.placeholder:SetFont(file, size, flags)
end

-- The windows' background (Options > Whispers > Windows): its look, color
-- and how dark it is
local BACKGROUND_COLORS = {
  dark = Constants.COLORS.codGray,
  black = { r = 0, g = 0, b = 0 },
  brown = { r = 0.12, g = 0.09, b = 0.06 },
  blue = { r = 0.05, g = 0.07, b = 0.12 },
  purple = { r = 0.1, g = 0.06, b = 0.11 },
}
local FADE_EDGE = 24 -- the soft edges of the "Fading edges" look

function ApplyBackground(window)
  local profile = Profile()
  -- (the chat's look: no box around it, like the chat)
  local style = Choice("whisperWindowStyle", "rounded", "none")
  local color = BACKGROUND_COLORS[profile.whisperWindowColor or "dark"] or BACKGROUND_COLORS.dark
  local alpha = WindowOpacity()
  local bg = window.bg

  if window.fadeLeft then
    window.fadeLeft:Hide()
    window.fadeRight:Hide()
  end
  bg:ClearAllPoints()
  bg:SetAllPoints()
  bg:Show()
  if bg.SetTextureSliceMargins then bg:SetTextureSliceMargins(0, 0, 0, 0) end

  if style == "none" then
    bg:Hide()
  elseif style == "rounded" then
    bg:SetTexture(BUBBLE_TEXTURE)
    bg:SetVertexColor(color.r, color.g, color.b, alpha)
    if bg.SetTextureSliceMargins then
      bg:SetTextureSliceMargins(8, 8, 8, 8)
      if bg.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
        bg:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
      end
    end
  elseif style == "fade" then
    -- Soft all around: solid in the middle, fading out a little past the
    -- window's edges, so no hard line shows anywhere
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", -FADE_EDGE / 2, FADE_EDGE / 2)
    bg:SetPoint("BOTTOMRIGHT", FADE_EDGE / 2, -FADE_EDGE / 2)
    bg:SetTexture(ASSETS.."whisperSoft")
    bg:SetVertexColor(color.r, color.g, color.b, alpha)
    if bg.SetTextureSliceMargins then
      bg:SetTextureSliceMargins(24, 24, 24, 24)
      if bg.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
        bg:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
      end
    end
  else
    bg:SetColorTexture(color.r, color.g, color.b, alpha)
  end
end

-- The messages' room in the window: up to its edges in the chat's look,
-- like the chat's lines
local function PlaceMessages(window, messages)
  messages = messages or window.messages
  local inset = Profile().whisperLook == "chat" and 0 or 8
  messages:ClearAllPoints()
  messages:SetPoint("TOPLEFT", inset, -TITLE_HEIGHT - 4)
  messages:SetPoint("BOTTOMRIGHT", -inset, INPUT_HEIGHT + 12)
end

-- The box to answer in, with the main chat's edit box look (Options > Edit
-- box: Minimal, Solid or Framed, and its opacity), in the whisper color
local INPUT_SHAPES = "Interface\\Addons\\Glass\\Glass\\Assets\\Tabs\\"
local INPUT_LINE_ALPHA = 0.8

local function InputShape(texture, file)
  texture:SetTexture(INPUT_SHAPES..file)
  if texture.SetTextureSliceMargins then
    texture:SetTextureSliceMargins(8, 8, 8, 8)
    if texture.SetTextureSliceMode and Enum and Enum.UITextureSliceMode then
      texture:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
    end
  end
end

local function StyleInput(window)
  local input = window.input
  if not input then return end
  local profile = Profile()
  local style = profile.editBoxStyle
  local opacity = profile.editBoxBackgroundOpacity or 0.6
  local dark = Constants.COLORS.codGray
  local conversation = window.conversation
  local r, g, b = WhisperColor(conversation and conversation.bn, false)

  if not input.lineLeft then
    Mixin(input, Core.Components.GradientBackgroundMixin)
    input.frameBorder = input:CreateTexture(nil, "BORDER")
    input.frameBorder:SetAllPoints()
    InputShape(input.frameBorder, "tabBorder")
    for _, side in ipairs({ "Left", "Right" }) do
      local line = input:CreateTexture(nil, "BORDER")
      line:SetColorTexture(1, 1, 1, 1)
      line:SetHeight(1)
      input["line"..side] = line
    end
    input.lineLeft:SetPoint("BOTTOMLEFT")
    input.lineLeft:SetPoint("BOTTOMRIGHT", input, "BOTTOM")
    input.lineRight:SetPoint("BOTTOMLEFT", input, "BOTTOM")
    input.lineRight:SetPoint("BOTTOMRIGHT")
  end

  local minimal = style ~= "solid" and style ~= "framed"
  input:SetGradientBackground(20, 120, dark, opacity)
  for _, texture in ipairs({ input.leftBg, input.centerBg, input.rightBg, input.lineLeft, input.lineRight }) do
    texture:SetShown(minimal)
  end
  input.lineLeft:SetGradient("HORIZONTAL", _G.CreateColor(r, g, b, 0), _G.CreateColor(r, g, b, INPUT_LINE_ALPHA))
  input.lineRight:SetGradient("HORIZONTAL", _G.CreateColor(r, g, b, INPUT_LINE_ALPHA), _G.CreateColor(r, g, b, 0))

  input.bg:SetShown(not minimal)
  if style == "framed" then
    InputShape(input.bg, "tabBackground")
    input.bg:SetVertexColor(dark.r, dark.g, dark.b, opacity)
  else
    input.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    if input.bg.ClearTextureSlice then input.bg:ClearTextureSlice() end
    input.bg:SetVertexColor(dark.r, dark.g, dark.b, opacity)
  end
  input.frameBorder:SetShown(style == "framed")
  input.frameBorder:SetVertexColor(r, g, b, 0.9)
end

local function CreateWindow(conversation)
  windowCount = windowCount + 1
  local window = CreateFrame("Frame", "GlassWhisperWindow"..windowCount, UIParent)
  window:SetFrameStrata("MEDIUM")
  window:SetToplevel(true)
  window:SetClampedToScreen(true)
  window:SetMovable(true)
  window:SetResizable(true)
  if window.SetResizeBounds then window:SetResizeBounds(200, 110, 700, 600) end
  window:EnableMouse(true)
  window.alpha, window.target = 1, 1

  local saved = Profile().whisperWindow
  window:SetSize(saved and saved.width or 360, saved and saved.height or 200)
  -- The others open a little lower and to the right, not on top of each other
  local shift = 20 * ((windowCount - 1) % 5)
  if saved and saved.point then
    window:SetPoint(saved.point, UIParent, saved.relativePoint or saved.point, (saved.x or 0) + shift, (saved.y or 0) - shift)
  else
    window:SetPoint("BOTTOMLEFT", _G.GlassFrame or UIParent, "TOPLEFT", 20 + shift, 40 - shift)
  end

  -- Background (Options), and a thin gold line under the title
  window.bg = window:CreateTexture(nil, "BACKGROUND")
  window.bg:SetAllPoints()
  ApplyBackground(window)

  local gold = Gold()
  window.line = window:CreateTexture(nil, "ARTWORK")
  window.line:SetColorTexture(1, 1, 1, 1)
  window.line:SetHeight(1)
  window.line:SetPoint("TOPLEFT", 0, -TITLE_HEIGHT)
  window.line:SetPoint("TOPRIGHT", 0, -TITLE_HEIGHT)
  -- (in the whisper color: pink, or blue for a Battle.net friend)
  local lr, lg, lb = WhisperColor(conversation.bn, false)
  window.line:SetGradient("HORIZONTAL", _G.CreateColor(lr, lg, lb, 0.6), _G.CreateColor(lr, lg, lb, 0))

  -- Title: the name; dragging it moves the window
  local titleBar = CreateFrame("Frame", nil, window)
  titleBar:SetPoint("TOPLEFT")
  titleBar:SetPoint("TOPRIGHT")
  titleBar:SetHeight(TITLE_HEIGHT)
  titleBar:EnableMouse(true)
  titleBar:RegisterForDrag("LeftButton")
  titleBar:SetScript("OnDragStart", function () window:StartMoving() end)
  titleBar:SetScript("OnDragStop", function ()
    window:StopMovingOrSizing()
    SavePosition(window)
  end)

  window.title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  window.title:SetPoint("LEFT", 8, 0)
  window.title:SetPoint("RIGHT", -50, 0)
  window.title:SetJustifyH("LEFT")
  window.title:SetWordWrap(false)
  window.title:SetTextColor(gold.r, gold.g, gold.b)

  local close = IconButton(titleBar, "close", 16)
  close:SetPoint("RIGHT", -4, 0)
  close:SetScript("OnClick", function () Remove(conversation) end)

  local minimize = IconButton(titleBar, "buttonMinimize", 14)
  minimize:SetPoint("RIGHT", close, "LEFT", -2, 0)
  minimize:SetScript("OnClick", function () Hide(conversation) end)

  -- Messages
  local messages = CreateView(window)
  PlaceMessages(window, messages)
  window.messages = messages

  -- The box to answer in: Enter sends and keeps it open for the next line
  local input = CreateFrame("EditBox", nil, window)
  input:SetPoint("BOTTOMLEFT", 6, 6)
  input:SetPoint("BOTTOMRIGHT", -20, 6)
  input:SetHeight(INPUT_HEIGHT)
  input:SetAutoFocus(false)
  input:SetFontObject(_G.ChatFontNormal)
  input:SetMaxLetters(255)
  input:SetTextInsets(6, 6, 0, 0)
  input.bg = input:CreateTexture(nil, "BACKGROUND")
  input.bg:SetAllPoints()
  window.conversation = conversation
  window.input = input
  StyleInput(window)
  window.placeholder = input:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  window.placeholder:SetPoint("LEFT", 6, 0)
  window.placeholder:SetText("Reply...")
  local function UpdatePlaceholder()
    window.placeholder:SetShown(input:GetText() == "" and not input:HasFocus())
  end
  input:SetScript("OnEditFocusGained", UpdatePlaceholder)
  input:SetScript("OnEditFocusLost", UpdatePlaceholder)
  input:SetScript("OnTextChanged", UpdatePlaceholder)
  input:SetScript("OnEscapePressed", function (self) self:ClearFocus() end)
  input:SetScript("OnEnterPressed", function (self)
    local text = self:GetText()
    if text == nil or text == "" then
      self:ClearFocus()
      return
    end
    SendWhisper(conversation, text)
    self:SetText("")
  end)
  window.input = input

  -- Clicking the window starts typing
  window:SetScript("OnMouseDown", function () input:SetFocus() end)

  -- Resize corner
  local resize = IconButton(window, "buttonResize", 12)
  resize:SetPoint("BOTTOMRIGHT", -2, 2)
  resize:SetScript("OnMouseDown", function () window:StartSizing("BOTTOMRIGHT") end)
  resize:SetScript("OnMouseUp", function ()
    window:StopMovingOrSizing()
    SavePosition(window)
  end)

  window:SetScript("OnUpdate", function (_, elapsed) UpdateFade(conversation, elapsed) end)

  -- Stays open until you minimize or close it: not in the game's list of
  -- windows Escape closes, which the game also closes by itself (a map,
  -- a loading screen...)
  window:SetScript("OnHide", function ()
    input:ClearFocus()
    if conversation.window == window and conversation.bubble then Layout() end
  end)

  ApplyFonts(window)
  window:Hide()
  return window
end

local function Title(conversation)
  return conversation.name or "?"
end

-- One line in the window
-- The text's color (Options): the whisper color, or one for every line
local TEXT_COLORS = {
  white = { r = 1, g = 1, b = 1 },
  silver = { r = 0.78, g = 0.78, b = 0.8 },
}

local function TextColor(conversation, entry)
  local choice = Choice("whisperTextColor", "white", "whisper")
  if choice == "gold" then
    local gold = Gold()
    return gold.r, gold.g, gold.b
  end
  local color = TEXT_COLORS[choice]
  if color then return color.r, color.g, color.b end
  return WhisperColor(conversation.bn, entry.out)
end

local function AddToWindow(conversation, entry)
  local window = conversation.window
  if not window then return end
  local r, g, b = TextColor(conversation, entry)
  local message = { text = entry.text, r = r, g = g, b = b, side = entry.out and "right" or "left" }
  if Profile().whisperShowNames ~= false then
    message.name = conversation.short or "?"
    message.nameR, message.nameG, message.nameB = PersonColor(conversation, false)
  end
  local style = Choice("whisperTimestamps", "hm", "chat")
  if style == "chat" then style = Profile().timestamps end
  if style == "hm" or style == "hms" then
    message.time = date(style == "hms" and "%H:%M:%S" or "%H:%M", entry.time or time())
  end
  -- The chat's look (Options): the line as the chat writes it, "[Name]
  -- whispers: text" or "To [Name]: text", in the whisper color, the name in
  -- their class color, with the chat's timestamps
  if Profile().whisperLook == "chat" then
    message.side = "chat"
    local text = entry.text
    if Readable(text) and type(text) == "string" then
      local name = "|c"..Hex(PersonColor(conversation, false)).."["..(conversation.short or "?").."]|r"
      if not conversation.bn and conversation.target then
        name = "|Hplayer:"..conversation.target.."|h"..name.."|h"
      end
      local pattern
      if conversation.bn then
        pattern = entry.out and _G.CHAT_BN_WHISPER_INFORM_GET or _G.CHAT_BN_WHISPER_GET
      else
        pattern = entry.out and _G.CHAT_WHISPER_INFORM_GET or _G.CHAT_WHISPER_GET
      end
      pattern = pattern or (entry.out and "To %s: " or "%s whispers: ")
      local stamp = message.time and ("|cff808080"..message.time.."|r ") or ""
      -- (Show names off: the text alone)
      local who = Profile().whisperShowNames == false and "" or pattern:format(name)
      message.text = stamp..who..text
    end
    message.name, message.time = nil, nil
  end
  -- Web links clickable, like in the chat
  message.text = Core:GetModule("TextProcessing"):Linkify(message.text)
  window.messages:AddMessage(message)
end

-- All the lines again, in the current look (after a change in Options)
local function FillWindow(conversation)
  conversation.window.title:SetTextColor(PersonColor(conversation, false))
  conversation.window.messages:Clear()
  -- What was said before
  local lines = conversation.earlier or {}
  if #lines > 0 then
    local gray = 0.5
    for _, entry in ipairs(lines) do AddToWindow(conversation, entry) end
    conversation.window.messages:AddMessage({ text = "Previous session", r = gray, g = gray, b = gray, side = "center" })
  end
  for _, entry in ipairs(conversation.session) do AddToWindow(conversation, entry) end
end

local function EnsureWindow(conversation)
  if conversation.window then return conversation.window end
  conversation.window = CreateWindow(conversation)
  conversation.window.title:SetText(Title(conversation))
  FillWindow(conversation)
  return conversation.window
end

----
-- The envelope: one small icon at the right end of the tab bar, fading with
-- it, with how many people wrote something new. A click lists the
-- conversations (name and their last line); a click on one opens it.

local ROW_HEIGHT = 18
local LIST_MAX_NAME = 160 -- longest a name gets in the list before "..."
local LIST_HIDE_AFTER = 1.5 -- seconds with the mouse away before the list closes

local envelope, list
local rows = {}

-- The person's color: their class, or the Battle.net blue
local function NameColor(conversation)
  if conversation.bn then
    local info = _G.ChatTypeInfo and _G.ChatTypeInfo.BN_WHISPER
    if info and info.r then return info.r, info.g, info.b end
  end
  local color = conversation.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[conversation.class]
  if color then return color.r, color.g, color.b end
  return WhisperColor(false, false)
end

local function UnreadCount()
  local count = 0
  for _, key in ipairs(order) do
    local conversation = conversations[key]
    if conversation and conversation.unread then count = count + 1 end
  end
  return count
end

-- The tab bar shows for a few seconds, like for a guild or party message
local function RevealTabBar()
  local tabBar = Core:GetModule("UIManager").dock
  if not tabBar or (tabBar.state and tabBar.state.mouseOver) then return end
  tabBar:Show()
  if Profile().tabBarFade ~= false and tabBar.HideDelay then
    tabBar:HideDelay(10)
  end
end

local function TextFont(fontString, size)
  local file = LSM:Fetch("font", (Profile().tabFont ~= "" and Profile().tabFont) or Profile().font)
  if file then fontString:SetFont(file, size or Profile().tabFontSize or 12, "") end
end

local function Row(i)
  if rows[i] then return rows[i] end
  local row = CreateFrame("Button", nil, list)
  row:SetHeight(ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 6, -6 - (i - 1) * ROW_HEIGHT)
  row:SetPoint("TOPRIGHT", -6, -6 - (i - 1) * ROW_HEIGHT)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row.highlight = row:CreateTexture(nil, "BACKGROUND")
  row.highlight:SetAllPoints()
  row.highlight:SetColorTexture(1, 1, 1, 0.06)
  row.highlight:Hide()
  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.name:SetPoint("LEFT", 4, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)
  TextFont(row.name)
  -- Someone with something new: the tabs' alert under the name (a line
  -- fading out at its ends, a soft glow around it), quieter, breathing slowly
  row.alert = CreateFrame("Frame", nil, row)
  row.alert:SetHeight(2)
  row.alert:SetPoint("TOP", row.name, "BOTTOM", 0, 1)
  row.alertLine = row.alert:CreateTexture(nil, "OVERLAY")
  row.alertLine:SetTexture(TAB_ASSETS.."alertLine")
  row.alertLine:SetAllPoints()
  row.alertLine:SetAlpha(0.8)
  row.alertGlow = row.alert:CreateTexture(nil, "ARTWORK")
  row.alertGlow:SetTexture(TAB_ASSETS.."alertGlow")
  row.alertGlow:SetBlendMode("ADD")
  row.alertGlow:SetHeight(16)
  row.alertGlow:SetPoint("LEFT")
  row.alertGlow:SetPoint("RIGHT")
  row.alertPulse = row.alertGlow:CreateAnimationGroup()
  row.alertPulse:SetLooping("BOUNCE")
  local breath = row.alertPulse:CreateAnimation("Alpha")
  breath:SetFromAlpha(0.6)
  breath:SetToAlpha(0.25)
  breath:SetDuration(0.8)
  breath:SetSmoothing("IN_OUT")
  row:SetScript("OnEnter", function (self) self.highlight:Show() end)
  row:SetScript("OnLeave", function (self) self.highlight:Hide() end)
  row:SetScript("OnClick", function (self, button)
    local conversation = self.conversation
    if not conversation then return end
    if button == "RightButton" then
      Remove(conversation)
    else
      list:Hide()
      Show(conversation, true)
    end
  end)
  rows[i] = row
  return row
end

local function FillList()
  if not list then return end
  local shown = 0
  local widest = 0
  -- Newest first
  for i = #order, 1, -1 do
    local conversation = conversations[order[i]]
    if conversation then
      shown = shown + 1
      local row = Row(shown)
      row.conversation = conversation
      -- Names only, in the color chosen in Options; someone with something
      -- new in the whisper color, with the alert under the name
      local wr, wg, wb = WhisperColor(conversation.bn, false)
      if conversation.unread then
        row.name:SetTextColor(wr, wg, wb, 1)
      else
        local r, g, b = PersonColor(conversation, false)
        row.name:SetTextColor(r, g, b, 0.75)
      end
      row.name:SetText(conversation.short or "?")
      local width = math.min(LIST_MAX_NAME, row.name:GetStringWidth() + 2)
      row.name:SetWidth(width)
      widest = math.max(widest, width)
      row.alert:SetWidth(math.max(10, width * 0.8))
      row.alertLine:SetVertexColor(wr, wg, wb, 1)
      row.alertGlow:SetVertexColor(wr, wg, wb, 1)
      if conversation.unread then
        row.alert:Show()
        if not row.alertPulse:IsPlaying() then row.alertPulse:Play() end
      else
        row.alertPulse:Stop()
        row.alert:Hide()
      end
      row:Show()
    end
  end
  for i = shown + 1, #rows do rows[i]:Hide() end
  list:SetHeight(12 + shown * ROW_HEIGHT)
  -- As wide as the longest name, with room for the dot
  list:SetWidth(widest + 32)
  if shown == 0 then list:Hide() end
end

local function CreateList()
  list = CreateFrame("Frame", "GlassWhisperList", UIParent)
  list:SetFrameStrata("DIALOG")
  list:SetClampedToScreen(true)
  list:EnableMouse(true)
  local dark = Constants.COLORS.codGray
  list.bg = list:CreateTexture(nil, "BACKGROUND")
  list.bg:SetAllPoints()
  list.bg:SetColorTexture(dark.r, dark.g, dark.b, Profile().whisperListOpacity or 0.7)
  local gold = Gold()
  list.line = list:CreateTexture(nil, "ARTWORK")
  list.line:SetColorTexture(1, 1, 1, 1)
  list.line:SetHeight(1)
  list.line:SetPoint("TOPLEFT")
  list.line:SetPoint("TOPRIGHT")
  -- (in the whisper color, like the windows' line)
  local lr, lg, lb = WhisperColor(false, false)
  list.line:SetGradient("HORIZONTAL", _G.CreateColor(lr, lg, lb, 0), _G.CreateColor(lr, lg, lb, 0.6))
  -- Closes by itself once the mouse is away for a moment
  list:SetScript("OnShow", function (self) self.away = 0 end)
  list:SetScript("OnUpdate", function (self, elapsed)
    if self:IsMouseOver() or envelope:IsMouseOver() then
      self.away = 0
    else
      self.away = (self.away or 0) + elapsed
      if self.away > LIST_HIDE_AFTER then self:Hide() end
    end
  end)
  table.insert(_G.UISpecialFrames, "GlassWhisperList")
  list:Hide()
end

-- The envelope's color when there's nothing new (Options); with news it
-- takes the whisper color and pulses
local ICON_COLORS = {
  white = { r = 1, g = 1, b = 1 },
  silver = { r = 0.75, g = 0.75, b = 0.78 },
}

local function IconColor()
  local choice = Profile().whisperIconColor or "gold"
  if choice == "whisper" then return WhisperColor(false, false) end
  local color = ICON_COLORS[choice] or Gold()
  return color.r, color.g, color.b
end

local ICONS = {
  envelope = "buttonWhisper",
  bubble = "buttonWhisperBubble",
  bubbles = "buttonWhisperBubbles",
}

-- Where the envelope sits (Options), plus a fine adjustment in pixels. It
-- stays in the tab bar's frame wherever it is, so it fades with it.
local function PlaceEnvelope()
  if not envelope then return end
  local size = Profile().whisperIconSize or 20
  -- Which icon (Options): the envelope, a speech bubble, or two
  local art = ICONS[Profile().whisperIconStyle or "envelope"] or ICONS.envelope
  envelope.icon:SetTexture(ASSETS..art)
  envelope.outline:SetTexture(ASSETS..art.."Outline")
  envelope.icon:SetSize(size, size)
  if envelope.glow then envelope.glow:SetSize(size * 1.7, size * 1.7) end
  envelope.outline:SetSize(size, size)
  envelope:SetSize(size + 24, size + 4)
  TextFont(envelope.count, math.max(10, math.floor(size * 0.65)))

  local tabBar = envelope:GetParent()
  local chat = _G.GlassFrame or tabBar
  local x, y = Profile().whisperIconOffsetX or 0, Profile().whisperIconOffsetY or 0
  local where = Profile().whisperIconPosition or "barRight"
  envelope:ClearAllPoints()
  envelope.outline:ClearAllPoints()
  envelope.count:ClearAllPoints()
  local leftSide = where == "barLeft" or where == "aboveLeft"
  if leftSide then
    -- (the number on the icon's left, toward the outside)
    envelope.outline:SetPoint("RIGHT", -2, 0)
    envelope.count:SetPoint("RIGHT", envelope.icon, "LEFT", -3, 0)
  else
    envelope.outline:SetPoint("LEFT", 2, 0)
    envelope.count:SetPoint("LEFT", envelope.icon, "RIGHT", 3, 0)
  end
  if where == "barInside" then
    envelope.outline:ClearAllPoints()
    envelope.count:ClearAllPoints()
    envelope.outline:SetPoint("RIGHT", -2, 0)
    envelope.count:SetPoint("RIGHT", envelope.icon, "LEFT", -3, 0)
    envelope:SetPoint("RIGHT", tabBar, "RIGHT", x, y)
  elseif where == "barLeft" then
    envelope:SetPoint("RIGHT", tabBar, "LEFT", -4 + x, y)
  elseif where == "aboveRight" then
    envelope:SetPoint("BOTTOMRIGHT", chat, "TOPRIGHT", x, 4 + y)
  elseif where == "aboveLeft" then
    envelope:SetPoint("BOTTOMLEFT", chat, "TOPLEFT", x, 4 + y)
  else
    envelope:SetPoint("LEFT", tabBar, "RIGHT", 4 + x, y)
  end
  envelope.leftSide = leftSide
end

local function UpdateEnvelope()
  if not envelope then return end
  local count = UnreadCount()
  local r, g, b = IconColor()
  if count > 0 then r, g, b = WhisperColor(false, false) end
  envelope.icon:SetVertexColor(r, g, b, (count > 0 or envelope.hover) and 1 or 0.7)
  envelope.count:SetText(count > 0 and count or "")
  envelope.count:SetTextColor(r, g, b)
  envelope.glow:SetVertexColor(r, g, b, 1)
  if count > 0 then
    envelope.glow:Show()
    if not envelope.pulse:IsPlaying() then envelope.pulse:Play() end
    if not envelope.glowPulse:IsPlaying() then envelope.glowPulse:Play() end
  else
    envelope.pulse:Stop()
    envelope.glowPulse:Stop()
    envelope.glow:Hide()
    envelope.icon:SetAlpha(1)
  end
  envelope:SetShown(enabled and #order > 0)
  if list and list:IsShown() then FillList() end
end

local function CreateEnvelope()
  local tabBar = Core:GetModule("UIManager").dock or UIParent
  envelope = CreateFrame("Button", nil, tabBar)
  envelope:SetFrameLevel(tabBar:GetFrameLevel() + 5)
  envelope:RegisterForClicks("LeftButtonUp")

  envelope.outline = envelope:CreateTexture(nil, "ARTWORK")
  envelope.outline:SetTexture(ASSETS.."buttonWhisperOutline")
  envelope.outline:SetVertexColor(0, 0, 0, 0.85)
  envelope.icon = envelope:CreateTexture(nil, "OVERLAY")
  envelope.icon:SetTexture(ASSETS.."buttonWhisper")
  envelope.icon:SetPoint("CENTER", envelope.outline)
  -- With something new: a soft light behind it, breathing, so it shows even
  -- when small
  envelope.glow = envelope:CreateTexture(nil, "BACKGROUND")
  envelope.glow:SetTexture(ASSETS.."whisperGlow")
  envelope.glow:SetBlendMode("ADD")
  envelope.glow:SetPoint("CENTER", envelope.outline)
  envelope.glow:Hide()
  envelope.glowPulse = envelope.glow:CreateAnimationGroup()
  envelope.glowPulse:SetLooping("BOUNCE")
  local breath = envelope.glowPulse:CreateAnimation("Alpha")
  breath:SetFromAlpha(0.6)
  breath:SetToAlpha(0.25)
  breath:SetDuration(0.8)
  breath:SetSmoothing("IN_OUT")

  envelope.count = envelope:CreateFontString(nil, "OVERLAY", "GameFontNormal")

  envelope.pulse = envelope.icon:CreateAnimationGroup()
  envelope.pulse:SetLooping("BOUNCE")
  local pulse = envelope.pulse:CreateAnimation("Alpha")
  pulse:SetFromAlpha(1)
  pulse:SetToAlpha(0.6)
  pulse:SetDuration(0.8)
  pulse:SetSmoothing("IN_OUT")

  -- A little animation when a new whisper arrives (Options), on the icon
  -- and its outline together:
  -- shake: tips one way and the other, smaller each time, ends straight
  -- pulse: grows and shrinks back, twice
  -- bounce: jumps up and lands, twice, the second jump lower
  -- spin: one full turn
  envelope.animations = { shake = {}, pulse = {}, bounce = {}, spin = {} }
  for _, texture in ipairs({ envelope.icon, envelope.outline }) do
    local shake = texture:CreateAnimationGroup()
    for order, degrees in ipairs({ 14, -26, 22, -16, 6 }) do
      local turn = shake:CreateAnimation("Rotation")
      turn:SetDegrees(degrees)
      turn:SetOrigin("CENTER", 0, 0)
      turn:SetDuration(0.09)
      turn:SetOrder(order)
      turn:SetSmoothing("IN_OUT")
    end
    table.insert(envelope.animations.shake, shake)

    local pulse = texture:CreateAnimationGroup()
    for order, scale in ipairs({ 1.35, 1 / 1.35, 1.25, 1 / 1.25 }) do
      local grow = pulse:CreateAnimation("Scale")
      grow:SetScale(scale, scale)
      grow:SetOrigin("CENTER", 0, 0)
      grow:SetDuration(0.14)
      grow:SetOrder(order)
      grow:SetSmoothing("IN_OUT")
    end
    table.insert(envelope.animations.pulse, pulse)

    local bounce = texture:CreateAnimationGroup()
    for order, step in ipairs({ { 7, "OUT" }, { -7, "IN" }, { 3, "OUT" }, { -3, "IN" } }) do
      local jump = bounce:CreateAnimation("Translation")
      jump:SetOffset(0, step[1])
      jump:SetDuration(order <= 2 and 0.16 or 0.1)
      jump:SetOrder(order)
      jump:SetSmoothing(step[2])
    end
    table.insert(envelope.animations.bounce, bounce)

    local spin = texture:CreateAnimationGroup()
    local turn = spin:CreateAnimation("Rotation")
    turn:SetDegrees(-360)
    turn:SetOrigin("CENTER", 0, 0)
    turn:SetDuration(0.5)
    turn:SetSmoothing("IN_OUT")
    table.insert(envelope.animations.spin, spin)
  end

  PlaceEnvelope()

  envelope:SetScript("OnClick", function (self)
    if not list then CreateList() end
    if list:IsShown() then
      list:Hide()
      return
    end
    list:ClearAllPoints()
    if self.leftSide then
      list:SetPoint("BOTTOMLEFT", self, "TOPLEFT", 0, 4)
    else
      list:SetPoint("BOTTOMRIGHT", self, "TOPRIGHT", 0, 4)
    end
    FillList()
    if #order > 0 then list:Show() end
  end)
  -- Shift + drag: moves it (the same as Move left / right and down / up)
  envelope:RegisterForDrag("LeftButton")
  envelope:SetScript("OnDragStart", function (self)
    if not IsShiftKeyDown() then return end
    local scale = self:GetEffectiveScale()
    local startX, startY = GetCursorPosition()
    local offsetX, offsetY = Profile().whisperIconOffsetX or 0, Profile().whisperIconOffsetY or 0
    self:SetScript("OnUpdate", function ()
      local x, y = GetCursorPosition()
      Profile().whisperIconOffsetX = math.floor(offsetX + (x - startX) / scale + 0.5)
      Profile().whisperIconOffsetY = math.floor(offsetY + (y - startY) / scale + 0.5)
      PlaceEnvelope()
    end)
  end)
  envelope:SetScript("OnDragStop", function (self)
    self:SetScript("OnUpdate", nil)
  end)
  envelope:SetScript("OnEnter", function (self)
    self.hover = true
    UpdateEnvelope()
  end)
  envelope:SetScript("OnLeave", function (self)
    self.hover = false
    UpdateEnvelope()
  end)
end

----
-- A sound of your choice when a whisper arrives (Options > Whispers > Sound),
-- on top of the game's own: one of the game's sounds, or one another addon
-- shares (SharedMedia)

-- The game's sounds offered, by their SOUNDKIT name (only the ones this
-- client has are listed)
local GAME_SOUNDS = {
  { "TELL_MESSAGE", "Whisper" },
  { "UI_BNET_TOAST", "Battle.net toast" },
  { "IG_PLAYER_INVITE", "Invite" },
  { "READY_CHECK", "Ready check" },
  { "RAID_WARNING", "Raid warning" },
  { "MAP_PING", "Map ping" },
  { "UI_GARRISON_TOAST_MISSION_COMPLETE", "Mission complete" },
  { "ALARM_CLOCK_WARNING_3", "Alarm clock" },
  { "UI_EPICLOOT_TOAST", "Epic loot" },
}
local SOUND_EVERY = 1 -- seconds at least between two sounds
local lastSound = 0

-- The choices for Options: { value, shown name }
function Whispers:SoundChoices()
  local list = { { "none", "Default" } }
  local kits = _G.SOUNDKIT or {}
  for _, entry in ipairs(GAME_SOUNDS) do
    if kits[entry[1]] then table.insert(list, { "kit:"..entry[1], entry[2] }) end
  end
  for _, name in ipairs(LSM:List("sound") or {}) do
    if name ~= "None" then table.insert(list, { "lsm:"..name, name }) end
  end
  return list
end

function Whispers:PlaySound(force)
  local choice = Profile().whisperSound or "none"
  if choice == "none" then return end
  local now = GetTime()
  if not force and now - lastSound < SOUND_EVERY then return end
  lastSound = now
  local kind, name = choice:match("^(%a+):(.+)$")
  if kind == "kit" then
    local kit = _G.SOUNDKIT and _G.SOUNDKIT[name]
    if kit then pcall(_G.PlaySound, kit, "Master") end
  elseif kind == "lsm" then
    local file = LSM:Fetch("sound", name, true)
    if file then pcall(_G.PlaySoundFile, file, "Master") end
  end
end

local function ShakeEnvelope()
  if not envelope then return end
  local groups = envelope.animations[Profile().whisperIconAnimation or "shake"]
  if not groups then return end -- "none"
  for _, list in pairs(envelope.animations) do
    for _, group in ipairs(list) do group:Stop() end
  end
  for _, group in ipairs(groups) do group:Play() end
end

-- Kept as before for the rest of the module: a listed conversation has
-- conversation.bubble = true
local function UpdateBubble()
  UpdateEnvelope()
end

local function CreateBubble()
  if not envelope then CreateEnvelope() end
  return true
end

function Layout()
  if enabled and #order > 0 and not envelope then CreateEnvelope() end
  UpdateEnvelope()
end

----
-- Conversations

local function RemoveFromOrder(key)
  for i, other in ipairs(order) do
    if other == key then
      table.remove(order, i)
      return
    end
  end
end

function Show(conversation, focus)
  local window = EnsureWindow(conversation)
  conversation.unread = false
  window.visibleUntil = GetTime() + (Profile().chatHoldTime or 10)
  window.alpha, window.target = 1, 1
  window:SetAlpha(1)
  window:Show()
  window:Raise()
  if focus then window.input:SetFocus() end
  UpdateBubble(conversation)
end

function Hide(conversation)
  if conversation.window then conversation.window:Hide() end
  UpdateBubble(conversation)
end

-- Closed: no bubble or window; what was said stays saved and comes back with
-- the next whisper
function Remove(conversation)
  if conversation.window then conversation.window:Hide() end
  conversation.bubble = nil
  conversation.unread = false
  if conversation.saved then conversation.saved.open = nil end
  RemoveFromOrder(conversation.key)
  Layout()
end

local function Open(conversation)
  if conversation.bubble then
    -- (moves to the newest place)
    RemoveFromOrder(conversation.key)
  else
    conversation.bubble = CreateBubble(conversation)
  end
  table.insert(order, conversation.key)
  if conversation.saved then conversation.saved.open = true end
  -- Too many: the oldest closed one without news goes
  while #order > MAX_CONVERSATIONS do
    local oldest = conversations[order[1]]
    if not oldest then table.remove(order, 1) else Remove(oldest) end
  end
  Layout()
end

local function GetConversation(key, fields)
  local conversation = conversations[key]
  if not conversation then
    local saved = Saved()[key]
    -- Saved by the first test version with the realm added ("w:name-realm")
    local realm = _G.GetNormalizedRealmName and _G.GetNormalizedRealmName()
    local oldKey = realm and key:sub(1, 2) == "w:" and (key.."-"..realm:lower())
    if not saved and oldKey and Saved()[oldKey] then
      saved = Saved()[oldKey]
      Saved()[oldKey] = nil
      Saved()[key] = saved
    end
    if not saved then
      saved = { lines = {} }
      Saved()[key] = saved
    end
    -- What was said in earlier sessions (this session's lines are added to
    -- the saved ones too)
    local earlier = {}
    for i, entry in ipairs(saved.lines or {}) do earlier[i] = entry end
    saved.lines = saved.lines or {}
    conversation = { key = key, saved = saved, earlier = earlier, session = {} }
    conversations[key] = conversation
  end
  for field, value in pairs(fields) do
    if value ~= nil then conversation[field] = value end
  end
  -- Kept for next time (only what can be read)
  local saved = conversation.saved
  -- (a Battle.net name is only good for this session)
  if conversation.bn then saved.name = nil else saved.name = conversation.name end
  saved.short = conversation.short
  saved.target = conversation.target
  saved.bn = conversation.bn
  saved.tag = conversation.tag
  saved.class = conversation.class
  return conversation
end

local function AddLine(conversation, text, outgoing)
  local entry = { time = time(), out = outgoing, text = text }
  table.insert(conversation.session, entry)
  while #conversation.session > 200 do table.remove(conversation.session, 1) end
  AddToWindow(conversation, entry)
  -- Saved: not secret text, and not when history is off
  if Readable(text) and type(text) == "string" and Profile().keepHistory ~= false then
    local lines = conversation.saved.lines
    table.insert(lines, { time = entry.time, out = outgoing, text = text })
    while #lines > MAX_LINES do table.remove(lines, 1) end
  end
end

local function OnWhisper(event, text, sender, guid, bnID)
  local kind = EVENTS[event]
  if not kind or not Readable(sender) or type(sender) ~= "string" or sender == "" then return end
  if not Readable(bnID) or not Readable(guid) then return end

  local conversation
  if kind.bn then
    local tag = BNetTag(bnID)
    local key = tag and ("bn:"..tag) or (bnID and ("bnid:"..bnID))
    if not key then return end
    local short = tag and tag:match("^[^#]+") or nil
    conversation = GetConversation(key, { bn = true, tag = tag, bnID = bnID, name = sender, short = short })
  else
    local target = WhisperTarget(sender)
    local class
    if guid and guid ~= "" and GetPlayerInfoByGUID then
      local _, englishClass = GetPlayerInfoByGUID(guid)
      if Readable(englishClass) then class = englishClass end
    end
    local short = Ambiguate and Ambiguate(target, "none") or sender
    conversation = GetConversation("w:"..target:lower(), {
      bn = false, target = target, name = short, short = short:match("^[^-]+") or short, class = class,
    })
  end

  Whispers.lastAt = GetTime()
  -- The sound of your choice, also with the window open
  if not kind.out then Whispers:PlaySound() end
  if not conversation.bubble then Open(conversation) end
  if conversation.window then conversation.window.title:SetText(Title(conversation)) end
  AddLine(conversation, text, kind.out)

  local window = conversation.window
  if window and window:IsShown() then
    window.visibleUntil = GetTime() + (Profile().chatHoldTime or 10)
  elseif not kind.out then
    conversation.unread = true
    RevealTabBar()
    ShakeEnvelope()
    -- (Options: open by itself, without taking the keyboard)
    if Profile().whisperAutoOpen then Show(conversation, false) end
  end
  UpdateBubble(conversation)
end

-- Conversations saved by the first test version, with your realm added to
-- the name ("w:name-realm"): back to the name alone
local function FixOldKeys()
  local realm = _G.GetNormalizedRealmName and _G.GetNormalizedRealmName()
  if not realm or realm == "" then return end
  local suffix = "-"..realm:lower()
  local renames = {}
  for key in pairs(Saved()) do
    if type(key) == "string" and key:sub(1, 2) == "w:" and key:sub(-#suffix) == suffix then
      renames[key] = key:sub(1, -#suffix - 1)
    end
  end
  for oldKey, key in pairs(renames) do
    local saved = Saved()[oldKey]
    Saved()[oldKey] = nil
    if not Saved()[key] then
      if type(saved.target) == "string" then saved.target = WhisperTarget(saved.target) end
      Saved()[key] = saved
    end
  end
end

-- The conversations open last session
local function RestoreOpen()
  FixOldKeys()
  for key, saved in pairs(Saved()) do
    if type(saved) == "table" and saved.open and type(saved.lines) == "table" then
      local fields = {
        bn = saved.bn, tag = saved.tag, target = saved.target, short = saved.short,
        class = saved.class, name = saved.name or saved.short,
      }
      -- A Battle.net friend's name for this session
      if saved.bn then
        local info = FindBNetFriend(saved.tag)
        if info then
          fields.bnID = info.bnetAccountID
          if info.accountName and Readable(info.accountName) then fields.name = info.accountName end
        end
      end
      Open(GetConversation(key, fields))
    end
  end
end

----
-- Turning it on and off

-- The game option (Options > Social > New Whispers): inline while the windows
-- are on, so the game opens no tabs; back to what it was when they're off
local function SetGameOption(on)
  if not (GetCVar and SetCVar) then return end
  local global = Core.db.global
  if on then
    global.whisperModesBefore = global.whisperModesBefore or {}
    for _, cvar in ipairs(CVARS) do
      local value = GetCVar(cvar)
      if value and value ~= "inline" then
        global.whisperModesBefore[cvar] = global.whisperModesBefore[cvar] or value
        pcall(SetCVar, cvar, "inline")
      end
    end
  elseif global.whisperModesBefore then
    for _, cvar in ipairs(CVARS) do
      if GetCVar(cvar) == "inline" then
        pcall(SetCVar, cvar, global.whisperModesBefore[cvar] or "popout")
      end
    end
    global.whisperModesBefore = nil
  end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function (_, event, text, sender, ...)
  local guid, bnID = select(10, ...)
  OnWhisper(event, text, sender, guid, bnID)
end)

-- Separate windows (tabs dragged out of the chat) are drawn by the game, not
-- by Glass, so the whispers they show don't go through Glass' chat: they're
-- left out there by the game's own message filter, while the whisper windows
-- are on. Only on separate windows (the chat's are left out by Glass), and
-- only whispers the window got (readable: secret ones stay, like in the chat).
local function SeparateWindowFilter(chatFrame, event, text, sender, ...)
  if not enabled or not EVENTS[event] or not chatFrame or chatFrame.isDocked then return false end
  local guid, bnID = select(10, ...)
  if not Readable(text) or not Readable(sender) or not Readable(guid) or not Readable(bnID) then return false end
  return true
end

local filterAdded = false
local function AddSeparateWindowFilter()
  if filterAdded then return end
  local add = (_G.ChatFrameUtil and _G.ChatFrameUtil.AddMessageEventFilter) or _G.ChatFrame_AddMessageEventFilter
  if not add then return end
  filterAdded = true
  for event in pairs(EVENTS) do add(event, SeparateWindowFilter) end
end

local function SetEnabled(on)
  on = on and true or false
  SetGameOption(on)
  if on then AddSeparateWindowFilter() end
  if on == enabled then return end
  enabled = on
  for event in pairs(EVENTS) do
    if on then events:RegisterEvent(event) else events:UnregisterEvent(event) end
  end
  if not on then
    for _, conversation in pairs(conversations) do
      if conversation.window then conversation.window:Hide() end
    end
  end
  Layout()
end

function Whispers:OnEnable()
  -- "Shake on new whisper" of a test version became "Animation"
  if Profile().whisperIconShake == false then Profile().whisperIconAnimation = "none" end
  Profile().whisperIconShake = nil
  -- "Names in the list" of a test version became "Name color"
  local profile = Profile()
  if profile.whisperListColor then
    profile.whisperNameColor = profile.whisperListColor
    profile.whisperListColor = nil
  end
  SetEnabled(Profile().whisperWindows ~= false)
  -- (a moment later: the Battle.net friends list and the chat are ready)
  C_Timer.After(3, function ()
    if enabled then RestoreOpen() end
  end)

  Core:Subscribe(UPDATE_CONFIG, function (key)
    if key == "whisperWindows" then
      SetEnabled(Profile().whisperWindows ~= false)
      if enabled and #order == 0 then RestoreOpen() end
    elseif key == "font" or key == "messageFontSize" or key == "whisperFontSize" or key == "whisperFont" then
      for _, conversation in pairs(conversations) do
        if conversation.window then ApplyFonts(conversation.window) end
      end
    elseif key == "whisperText" then
      for _, conversation in pairs(conversations) do
        if conversation.window then FillWindow(conversation) end
      end
      UpdateEnvelope()
    elseif key == "whisperLook" then
      for _, conversation in pairs(conversations) do
        if conversation.window then
          ApplyBackground(conversation.window)
          PlaceMessages(conversation.window)
          ApplyFonts(conversation.window)
          FillWindow(conversation)
        end
      end
      UpdateEnvelope()
    elseif key == "whisperWindowOpacity" then
      for _, conversation in pairs(conversations) do
        if conversation.window then ApplyBackground(conversation.window) end
      end
    elseif key == "editBoxStyle" or key == "editBoxBackgroundOpacity" then
      for _, conversation in pairs(conversations) do
        if conversation.window then StyleInput(conversation.window) end
      end
    elseif key == "whisperSound" then
      -- (a new choice: heard right away)
      Whispers:PlaySound(true)
    elseif key == "whisperIconAnimation" then
      -- (a new choice: seen right away)
      ShakeEnvelope()
    elseif key == "whisperIcon" then
      if list then
        local dark = Constants.COLORS.codGray
        list.bg:SetColorTexture(dark.r, dark.g, dark.b, Profile().whisperListOpacity or 0.7)
      end
      PlaceEnvelope()
      UpdateEnvelope()
    end
  end)
end
