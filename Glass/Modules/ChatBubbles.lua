local Core, Constants = unpack(select(2, ...))
local ChatBubbles = Core:GetModule("ChatBubbles")

-- luacheck: push ignore 113
local CreateColor = CreateColor
local CreateFrame = CreateFrame
local C_ChatBubbles = C_ChatBubbles
-- luacheck: pop

local UPDATE_CONFIG = Constants.EVENTS.UPDATE_CONFIG

-- A value the game keeps secret (in dungeons and raids): can't be read
local function Secret(value)
  return _G.issecretvalue and _G.issecretvalue(value) or false
end

----
-- ChatBubbles Module
--
-- The bubbles over characters' heads (say, yell, party, NPCs) in the Glass
-- look (Options > Chat bubbles): the game's white-bordered box and its tail
-- hidden, a background in the style chosen (Glass, Solid, Rounded or
-- Underline), a thin line in the message's color, the Glass font, a little
-- higher over the character. The game reuses its bubbles, so each one is
-- styled once and only looked at again when it shows a new message.
-- Bubbles in dungeons and raids are locked by the game (addons can't change
-- them), so there they keep the game's look.

local ASSETS = "Interface\\AddOns\\Glass\\Glass\\Assets\\"
local ROUNDED_TEXTURE = ASSETS.."Buttons\\whisperBubble" -- the whisper windows' rounded box
local TAIL_TEXTURE = ASSETS.."bubbleTail"

local BUBBLE_FADE = 18 -- Glass style: how far the background fades out, left and right
local LINE_ALPHA = 0.55 -- the line along an edge, same as the alerts'
local BAR_ALPHA = 0.9 -- the line on the left (a bar), stronger: it's short
local BAR_WIDTH = 2
local NAME_GAP = 2 -- room under the speaker's name
-- The background around the text, tighter than the game's box (16 all
-- round, made for its thick border): the bubble is smaller, and with the
-- name over the text it no longer grows too big
local PAD_X, PAD_Y = 10, 6
local MIN_WIDTH = 60 -- a short message ("hi"): the box at least this wide, the text in its middle
local TAIL_WIDTH, TAIL_HEIGHT = 16, 8
local SCAN_TIME = 0.3 -- after a message, how long to look for its bubble

-- Messages that can show a bubble
local BUBBLE_EVENTS = {
  "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_MONSTER_SAY", "CHAT_MSG_MONSTER_YELL", "CHAT_MSG_MONSTER_PARTY",
}

local styled = setmetatable({}, { __mode = "k" }) -- holder -> true, bubbles in the Glass look
local recent = {} -- message text -> { color, name, guid }, for the messages whose bubbles are being looked for

local function Profile() return Core.db.profile end

---
-- The frame with the bubble's box and text: a child of the bubble in the
-- current game, the bubble itself in older ones.
local function Holder(bubble)
  if bubble.glassHolder then return bubble.glassHolder end
  local holder = bubble
  for _, child in ipairs({ bubble:GetChildren() }) do
    if child.String then
      holder = child
      break
    end
  end
  bubble.glassHolder = holder
  return holder
end

local function Text(holder)
  if holder.String then return holder.String end
  for _, region in ipairs({ holder:GetRegions() }) do
    if region:IsObjectType("FontString") and region ~= holder.glassName and region ~= holder.glassCopy then return region end
  end
end

---
-- The text shown: a copy of the game's, a little higher (Options: Height).
-- The game's own text is never moved: once an addon anchors it, the game
-- stops moving it with the character (the bubble stayed where it first
-- showed, even over someone else). So the game's is only made see-through,
-- and the copy, anchored to it, goes wherever the game puts it.
local function PlaceCopy(holder)
  local text, copy = Text(holder), holder.glassCopy
  if not (text and copy) then return end
  local lift = Profile().bubbleLift or 20
  if copy.glassLift == lift then return end
  copy.glassLift = lift
  copy:ClearAllPoints()
  copy:SetPoint("CENTER", text, "CENTER", 0, lift)
end

---
-- The copy's width: the game sized its text for its own letters, before
-- the Glass font went on, so the same width cut the end off ("doi...").
-- One line: as wide as it needs. Longer: the game's width, wrapping.
local WRAP_SLACK = 1.3 -- up to this much wider than the game's text, it stays on one line
local function SizeCopy(text, copy)
  local width = text:GetWidth()
  local need = (copy.GetUnboundedStringWidth and copy:GetUnboundedStringWidth()) or copy:GetStringWidth()
  if need and need > 0 and need <= width * WRAP_SLACK + 4 then width = need + 1 end
  if copy.glassWidth ~= width then
    copy.glassWidth = width
    copy:SetWidth(width)
  end
end

---
-- The copy the same as the game's text: its words, and its color unless
-- another was chosen (Options: Text color)
local function SyncCopy(holder)
  local text, copy = Text(holder), holder.glassCopy
  if not (text and copy) then return end
  local shown = text:GetText()
  -- (a secret text can't be compared: put on as it is)
  if Secret(shown) or copy:GetText() ~= shown then copy:SetText(shown) end
  local justify = text:GetJustifyH()
  if copy:GetJustifyH() ~= justify then copy:SetJustifyH(justify) end
  SizeCopy(text, copy)
  local want = holder.glassColor
  local r, g, b
  if want then
    r, g, b = want[1], want[2], want[3]
  else
    r, g, b = text:GetTextColor()
  end
  local cr, cg, cb = copy:GetTextColor()
  if cr ~= r or cg ~= g or cb ~= b then copy:SetTextColor(r, g, b) end
  if text:GetAlpha() > 0 then text:SetAlpha(0) end
end

local function Opacity()
  local own = Profile().bubbleOpacity or 0
  if own > 0 then return own end
  -- Default: a little darker than the chat's, to read over any ground (but
  -- see-through: the world behind it still shows)
  return math.min(0.75, Profile().chatBackgroundOpacity + 0.25)
end

local function FontFile()
  return Core.Libs.LSM:Fetch(Core.Libs.LSM.MediaType.FONT, Profile().font)
end

-- The class color of a player, by the message's GUID (nil: not a player)
local function ClassColor(guid)
  if not (guid and guid ~= "" and _G.GetPlayerInfoByGUID) then return end
  local ok, _, class = pcall(_G.GetPlayerInfoByGUID, guid)
  local color = ok and class and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[class]
  if color then return color.r, color.g, color.b end
end

---
-- The Glass parts of a bubble, made once (each bubble is reused)
local function Build(holder)
  -- The Glass style's background (three parts, fading out at the ends)
  Core.Components.GradientBackgroundMixin.SetGradientBackground(holder, BUBBLE_FADE, BUBBLE_FADE, Constants.COLORS.codGray, Opacity())
  -- Solid and Rounded: one texture
  holder.glassFill = holder:CreateTexture(nil, "BACKGROUND")
  for _, texture in ipairs({ holder.leftBg, holder.centerBg, holder.rightBg, holder.glassFill }) do
    texture:SetDrawLayer("BACKGROUND", -8)
  end
  -- The line: two halves fading out at the ends (top or bottom), or a bar on the left
  holder.glassLineA = holder:CreateTexture(nil, "ARTWORK")
  holder.glassLineB = holder:CreateTexture(nil, "ARTWORK")
  holder.glassBar = holder:CreateTexture(nil, "ARTWORK")
  for _, line in ipairs({ holder.glassLineA, holder.glassLineB, holder.glassBar }) do
    line:SetColorTexture(1, 1, 1, 1)
  end
  -- The point under the bubble, toward who's talking
  holder.glassTail = holder:CreateTexture(nil, "BACKGROUND")
  holder.glassTail:SetTexture(TAIL_TEXTURE)
  holder.glassTail:SetSize(TAIL_WIDTH, TAIL_HEIGHT)
  -- Who's talking, over the text
  holder.glassName = holder:CreateFontString(nil, "OVERLAY")
  -- The text shown (PlaceCopy)
  holder.glassCopy = holder:CreateFontString(nil, "ARTWORK")
  holder.glassCopy:SetWordWrap(true)
  if holder.glassCopy.SetNonSpaceWrap then holder.glassCopy:SetNonSpaceWrap(true) end
  holder.glassCopy:SetJustifyV("MIDDLE")

  holder.glassBubbleParts = { holder.leftBg, holder.centerBg, holder.rightBg, holder.glassFill,
    holder.glassLineA, holder.glassLineB, holder.glassBar, holder.glassTail, holder.glassName, holder.glassCopy }

  -- The game's box and tail: everything else drawn on the bubble
  local own = {}
  for _, part in ipairs(holder.glassBubbleParts) do own[part] = true end
  holder.glassBubbleHidden = {}
  for _, region in ipairs({ holder:GetRegions() }) do
    if region:IsObjectType("Texture") and not own[region] then
      table.insert(holder.glassBubbleHidden, region)
    end
  end
  if holder.Tail and not own[holder.Tail] then
    table.insert(holder.glassBubbleHidden, holder.Tail)
  end

  local text = Text(holder)
  if text then
    holder.glassGameFont = { text:GetFont() }
  end
end

---
-- The text: the Glass font, its size and color (Options)
local function Font(holder)
  local text = Text(holder)
  if not text then return end
  local profile = Profile()
  local game = holder.glassGameFont or {}
  local size = (profile.bubbleFontSize or 0) > 0 and profile.bubbleFontSize or game[2] or 14
  -- (the game's text too, unseen: the game sizes the bubble by it, and the
  -- copy wraps the same way)
  text:SetFont(FontFile(), size, profile.fontFlags)
  local copy = holder.glassCopy
  copy:SetFont(FontFile(), size, profile.fontFlags)
  copy:SetShadowColor(0, 0, 0, 1)
  copy:SetShadowOffset(1, -1)

  -- The color (Options: Text color). Default: the game's, followed by the
  -- copy (SyncCopy: the game sets it a moment after the bubble shows; it's
  -- already the channel's color)
  holder.glassColor = profile.bubbleTextColor == "white" and { 1, 1, 1 } or nil

  local name = holder.glassName
  name:SetFont(FontFile(), math.max(8, size - 3), profile.fontFlags)
  name:SetShadowColor(0, 0, 0, 1)
  name:SetShadowOffset(1, -1)
end

---
-- The line's color (Options: Line color): the message's channel, gold,
-- white or none (nil)
local function LineColor(holder)
  local choice = Profile().bubbleLineColor
  if choice == "none" then return end
  if choice == "white" then return 1, 1, 1 end
  local info = holder.glassInfo
  if choice ~= "gold" and info and info.color then return info.color.r, info.color.g, info.color.b end
  local gold = Constants.COLORS.apache
  return gold.r, gold.g, gold.b
end

---
-- A part placed on the Glass box: point of the part, point of the box, and
-- an offset. The box is the text with PAD_X/PAD_Y around it, and top more
-- above it (the name); without the text, the game's box.
local function At(holder, region, point, boxPoint, x, y)
  local text = holder.glassCopy or Text(holder)
  local base, dx, dy = holder, 0, 0
  if text then
    base = text
    -- (Options: Bubble size, room added all around the text)
    local extra = holder.glassPad or 0
    local padX, padY = PAD_X + extra, PAD_Y + extra
    dx = boxPoint:find("LEFT") and -padX or boxPoint:find("RIGHT") and padX or 0
    dy = boxPoint:find("TOP") and padY or boxPoint:find("BOTTOM") and -padY or 0
  end
  if boxPoint:find("TOP") then dy = dy + (holder.glassTop or 0) end
  if boxPoint:find("RIGHT") then dx = dx + (holder.glassWide or 0) + (holder.glassSide or 0) end
  if boxPoint:find("LEFT") then dx = dx - (holder.glassSide or 0) end
  region:SetPoint(point, base, boxPoint, dx + (x or 0), dy + (y or 0))
end

---
-- Everything placed and colored for the options and the message shown
local function Layout(holder)
  local profile = Profile()
  local look = profile.bubbleLook or "glass"
  local info = holder.glassInfo
  local opacity = Opacity()
  local dark = Constants.COLORS.codGray

  Font(holder)
  -- (the copy's words and width first: the name and the box go by them;
  -- shown again: Glass look turned off hid it)
  PlaceCopy(holder)
  SyncCopy(holder)
  holder.glassCopy:Show()

  -- Who's talking (Options: Name of who's talking), over the text: the
  -- background grows up to take it in
  local name = holder.glassName
  local top = 0
  if profile.bubbleShowName and info and info.name and info.name ~= "" then
    name:SetText(info.name)
    local r, g, b = ClassColor(info.guid)
    if not r then
      local gold = Constants.COLORS.apache
      r, g, b = gold.r, gold.g, gold.b
    end
    name:SetTextColor(r, g, b)
    name:ClearAllPoints()
    name:SetPoint("BOTTOMLEFT", holder.glassCopy, "TOPLEFT", 0, NAME_GAP)
    name:Show()
    top = name:GetStringHeight() + NAME_GAP
  else
    name:Hide()
  end
  holder.glassTop = top
  holder.glassPad = profile.bubblePadding or 0
  -- A short message: room on both sides, up to MIN_WIDTH (the Glass
  -- style's fading ends took nearly all of a narrow box)
  local copyWidth = holder.glassCopy:GetWidth()
  local side = math.max(0, (MIN_WIDTH - copyWidth) / 2)
  holder.glassSide = side
  -- A name longer than that: the box as wide as the name
  local wide = 0
  if name:IsShown() then wide = math.max(0, name:GetStringWidth() - copyWidth - side * 2) end
  holder.glassWide = wide
  if name:IsShown() then
    name:ClearAllPoints()
    name:SetPoint("BOTTOMLEFT", holder.glassCopy, "TOPLEFT", -side, NAME_GAP)
  end

  -- Background
  local glass = look == "glass"
  for _, texture in ipairs({ holder.leftBg, holder.centerBg, holder.rightBg }) do texture:SetShown(glass) end
  if glass then
    Core.Components.GradientBackgroundMixin.SetGradientBackground(holder, BUBBLE_FADE, BUBBLE_FADE, dark, opacity)
    for _, texture in ipairs({ holder.leftBg, holder.rightBg }) do texture:ClearAllPoints() end
    At(holder, holder.leftBg, "TOPLEFT", "TOPLEFT")
    At(holder, holder.leftBg, "BOTTOMLEFT", "BOTTOMLEFT")
    At(holder, holder.rightBg, "TOPRIGHT", "TOPRIGHT")
    At(holder, holder.rightBg, "BOTTOMRIGHT", "BOTTOMRIGHT")
  end
  local fill = holder.glassFill
  if look == "solid" or look == "rounded" then
    if look == "rounded" then
      fill:SetTexture(ROUNDED_TEXTURE)
      if fill.SetTextureSliceMargins then
        fill:SetTextureSliceMargins(8, 8, 8, 8)
        if fill.SetTextureSliceMode and _G.Enum and _G.Enum.UITextureSliceMode then
          fill:SetTextureSliceMode(_G.Enum.UITextureSliceMode.Stretched)
        end
      end
    else
      fill:SetTexture("Interface\\Buttons\\WHITE8x8")
      if fill.ClearTextureSlice then fill:ClearTextureSlice() end
    end
    fill:SetVertexColor(dark.r, dark.g, dark.b, opacity)
    fill:ClearAllPoints()
    At(holder, fill, "TOPLEFT", "TOPLEFT")
    At(holder, fill, "BOTTOMRIGHT", "BOTTOMRIGHT")
    fill:Show()
  else
    fill:Hide()
  end

  -- The point under the bubble (Options: Pointer), the background's color;
  -- not with Underline (no background)
  local tail = holder.glassTail
  if profile.bubbleTail and look ~= "underline" then
    tail:SetVertexColor(dark.r, dark.g, dark.b, opacity)
    tail:ClearAllPoints()
    At(holder, tail, "TOP", "BOTTOM")
    tail:Show()
  else
    tail:Hide()
  end

  -- The line (Options: Line color, Line position; Underline: always under)
  local r, g, b = LineColor(holder)
  local where = look == "underline" and "bottom" or profile.bubbleLinePosition or "top"
  local a, b2, bar = holder.glassLineA, holder.glassLineB, holder.glassBar
  if not r then
    a:Hide() b2:Hide() bar:Hide()
  elseif where == "left" then
    a:Hide() b2:Hide()
    -- (inside the corners of the rounded box)
    local inset = look == "rounded" and 4 or 0
    bar:ClearAllPoints()
    At(holder, bar, "TOPLEFT", "TOPLEFT", inset > 0 and 2 or 0, -inset)
    At(holder, bar, "BOTTOMLEFT", "BOTTOMLEFT", inset > 0 and 2 or 0, inset)
    bar:SetWidth(BAR_WIDTH)
    bar:SetVertexColor(r, g, b, BAR_ALPHA)
    bar:Show()
  else
    bar:Hide()
    local edge = where == "bottom" and "BOTTOM" or "TOP"
    a:ClearAllPoints()
    At(holder, a, edge.."LEFT", edge.."LEFT")
    At(holder, a, edge.."RIGHT", edge)
    b2:ClearAllPoints()
    At(holder, b2, edge.."LEFT", edge)
    At(holder, b2, edge.."RIGHT", edge.."RIGHT")
    a:SetHeight(1)
    b2:SetHeight(1)
    a:SetGradient("HORIZONTAL", CreateColor(r, g, b, 0), CreateColor(r, g, b, LINE_ALPHA))
    b2:SetGradient("HORIZONTAL", CreateColor(r, g, b, LINE_ALPHA), CreateColor(r, g, b, 0))
    a:Show()
    b2:Show()
  end

  PlaceCopy(holder)
  SyncCopy(holder)
end

---
-- While a bubble shows: kept at its height and color. The game places its
-- text again a moment after it shows (it went back down after a second), so
-- it's checked every frame while any bubble is up, and nothing runs when
-- none is.
local visible = {} -- holder -> true, Glass bubbles on the screen
local keeper = CreateFrame("Frame")
keeper:Hide()

local function Keep(holder)
  PlaceCopy(holder)
  SyncCopy(holder)
end

keeper:SetScript("OnUpdate", function (self)
  local any = false
  for holder in pairs(visible) do
    any = true
    Keep(holder)
  end
  if not any then self:Hide() end
end)

local function Watch(holder, on)
  visible[holder] = on or nil
  if on then keeper:Show() end
end

---
-- A new message in the bubble: who said it and in which channel, found by
-- its text among the messages just received (the game reuses a bubble for
-- anyone and any kind of message)
local function Message(holder)
  local text = Text(holder)
  local shown = text and text:GetText()
  if Secret(shown) then shown = nil end
  if shown == holder.glassText then return false end
  holder.glassText = shown
  holder.glassInfo = shown and recent[shown]
  return true
end

local function Style(bubble)
  if bubble:IsForbidden() then return end
  local holder = Holder(bubble)
  if styled[holder] then
    if Message(holder) then Layout(holder) end
    return
  end
  styled[holder] = true
  if not holder.glassBubbleParts then
    Build(holder)
    -- (on the screen or not: the game shows and hides the bubble itself)
    bubble:HookScript("OnShow", function () if styled[holder] then Watch(holder, true) end end)
    bubble:HookScript("OnHide", function () Watch(holder, false) end)
  end
  Watch(holder, bubble:IsShown())
  -- See-through, not hidden: the game doesn't change their opacity
  for _, region in ipairs(holder.glassBubbleHidden) do region:SetAlpha(0) end
  Message(holder)
  Layout(holder)
end

---
-- Back to the game's look (the option turned off)
local function Unstyle(holder)
  styled[holder] = nil
  Watch(holder, false)
  for _, part in ipairs(holder.glassBubbleParts or {}) do part:Hide() end
  for _, region in ipairs(holder.glassBubbleHidden or {}) do region:SetAlpha(1) end
  local text = Text(holder)
  local font = holder.glassGameFont
  if text and font and font[1] then text:SetFont(font[1], font[2], font[3]) end
  if text then text:SetAlpha(1) end
  if holder.glassCopy then holder.glassCopy.glassLift = nil end
  holder.glassText, holder.glassInfo, holder.glassColor = nil, nil, nil
end

local function StyleAll()
  for _, bubble in ipairs(C_ChatBubbles.GetAllChatBubbles()) do
    Style(bubble)
  end
end

function ChatBubbles:OnEnable()
  if not C_ChatBubbles or not C_ChatBubbles.GetAllChatBubbles then return end

  -- A bubble shows a moment after its message: looked for over a few
  -- frames after each message, then this stops (nothing runs in between)
  local scanner = CreateFrame("Frame")
  scanner:Hide()
  local timeLeft = 0
  scanner:SetScript("OnUpdate", function (self, elapsed)
    StyleAll()
    timeLeft = timeLeft - elapsed
    if timeLeft <= 0 then
      self:Hide()
      wipe(recent)
    end
  end)
  scanner:SetScript("OnEvent", function (self, event, message, sender, ...)
    local color = _G.ChatTypeInfo and _G.ChatTypeInfo[event:sub(10)]
    -- (secret messages, in dungeons and raids: can't be kept or looked
    -- for, and their bubbles are the game's own there anyway)
    if message and not Secret(message) then
      local name = not Secret(sender) and sender or nil
      if name and _G.Ambiguate then name = _G.Ambiguate(name, "short") end
      local guid = select(10, ...)
      recent[message] = { color = color and color.r and color, name = name, guid = not Secret(guid) and guid or nil }
    end
    timeLeft = SCAN_TIME
    self:Show()
  end)

  local function Apply()
    if Profile().bubbleStyle then
      for _, event in ipairs(BUBBLE_EVENTS) do scanner:RegisterEvent(event) end
      StyleAll()
    else
      scanner:UnregisterAllEvents()
      scanner:Hide()
      wipe(recent)
      for holder in pairs(styled) do Unstyle(holder) end
    end
  end
  Apply()

  Core:Subscribe(UPDATE_CONFIG, function (key)
    if key == "bubbleStyle" then
      Apply()
    elseif key == "chatBackgroundOpacity" or key == "font" or key == "fontFlags"
      or (type(key) == "string" and key:find("^bubble")) then
      for holder in pairs(styled) do Layout(holder) end
    end
  end)
end
