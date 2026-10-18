local Core, _, Utils = unpack(select(2, ...))
local TP = Core:GetModule("TextProcessing")

-- luacheck: push ignore 113
local strjoin = strjoin
local strsplit = strsplit
-- luacheck: pop

---
--Takes a texture escape string and adjusts its yOffset
local function adjustTextureYOffset(texture)
  -- Texture has 14 parts
  -- path, height, width, offsetX, offsetY,
  -- texWidth, texHeight
  -- leftTex, topTex, rightTex, bottomText,
  -- rColor, gColor, bColor

  -- Strip escape characters
  -- Split into parts
  local parts = {strsplit(':', strsub(texture, 3, -3))}
  local yOffset = Core.db.profile.iconTextureYOffset

  if #parts < 5 then
    -- Pad out ommitted attributes
    for i=1, 5 do
      if parts[i] == nil then
        if i == 3 then
          -- If width is not specified, the width should equal the height
          parts[i] = parts[2]
        else
          parts[i] = '0'
        end
      end
    end
  end

  -- Adjust yOffset by configured amount
  parts[5] = tostring(tonumber(parts[5]) - yOffset)

  -- Rejoin string and readd escape codes
  return '|T'..strjoin(':', unpack(parts))..'|t'
end


---
-- Gets all inline textures found in the string and adjusts their yOffset
local function textureProcessor(text)
  local cursor = 1
  local origLen = strlen(text)

  local parts = {}

  while cursor <= origLen do
    local mStart, mEnd = strfind(text, '%|T.-%|t', cursor)

    if mStart then
      table.insert(parts, strsub(text, cursor, mStart - 1))
      table.insert(parts, adjustTextureYOffset(strsub(text, mStart, mEnd)))
      cursor = mEnd + 1
    else
      -- No more matches
      table.insert(parts, strsub(text, cursor, origLen))
      cursor = origLen + 1
    end
  end

  return strjoin("", unpack(parts))
end

---
-- Adds Prat Timestamps if configured
local function pratTimestampProcessor(text)
  return _G.Prat.Addon:GetModule("Timestamps"):InsertTimeStamp(text)
end

---
-- Turns web addresses into clickable links. Clicking one opens a window with
-- the address selected, so it can be copied (see Hyperlinks and Copy).
local URL_COLOR = "|cff6fb7ff"
local URL_CHARS = "[%w%-%._~:/%?#%[%]@!%$&'%*%+,;=%%]"

local function wrapUrl(match)
  -- Leave trailing punctuation (end of a sentence) outside the link
  local url, trail = match:match("^(.-)([%.,!%?;:'%]]*)$")
  if url == "" then return match end
  return URL_COLOR.."|Hglassurl:"..url.."|h["..url.."]|h|r"..trail
end

local function linkifySegment(segment)
  segment = segment:gsub("https?://"..URL_CHARS.."+", wrapUrl)
  -- "www." only at the start of a word, so it doesn't match inside links made above
  segment = segment:gsub("%f[%S]www%."..URL_CHARS.."+", wrapUrl)
  return segment
end

local function urlProcessor(text)
  -- Only look at the text between existing links (items, players, etc.)
  local parts = {}
  local cursor = 1

  while true do
    local mStart, mEnd = strfind(text, "|H.-|h.-|h", cursor)
    if not mStart then
      table.insert(parts, linkifySegment(strsub(text, cursor)))
      break
    end
    table.insert(parts, linkifySegment(strsub(text, cursor, mStart - 1)))
    table.insert(parts, strsub(text, mStart, mEnd))
    cursor = mEnd + 1
  end

  return table.concat(parts)
end

---
-- Short channel names: [1. General - Zone] -> [1], [Party Leader] -> [PL], ...
-- Group channels are recognised by their link data, which doesn't change with
-- the game language. Leader variants are told apart by the game's own strings.
local SHORT_CHANNELS = {
  PARTY = { "P", "PL" },
  RAID = { "R", "RL" },
  INSTANCE_CHAT = { "I", "IL" },
  GUILD = { "G" },
  OFFICER = { "O" },
}

local function shortChannelName(data, name)
  -- Numbered channels: keep only the number
  local number = name:match("^(%d+)%.")
  if number then return number end

  local kind = data:match("^channel:(%u[%u_]*)$")
  local short = kind and SHORT_CHANNELS[kind]
  if not short then return nil end

  local leaderName = _G["CHAT_MSG_"..kind.."_LEADER"]
  if short[2] and leaderName and name == leaderName then
    return short[2]
  end
  return short[1]
end

-- Channel notices ("Changed Channel: [1. General - City]", "Joined Channel:
-- ...") keep the full name, so you can see which channel a number is. They're
-- recognised by the game's own texts, which follow the game language.
local CHANNEL_NOTICES = {
  "CHAT_YOU_CHANGED_NOTICE", "CHAT_YOU_JOINED_NOTICE", "CHAT_YOU_LEFT_NOTICE",
  "CHAT_SUSPENDED_NOTICE", "CHAT_YOU_CHANGED_NOTICE_BN", "CHAT_YOU_JOINED_NOTICE_BN",
  "CHAT_YOU_LEFT_NOTICE_BN", "CHAT_SUSPENDED_NOTICE_BN",
}

local function isChannelNotice(text)
  for _, key in ipairs(CHANNEL_NOTICES) do
    local format = _G[key]
    -- The part before the channel link, e.g. "Changed Channel: "
    local prefix = type(format) == "string" and format:match("^(.-)|H")
    if prefix and prefix ~= "" and strfind(text, prefix, 1, true) then
      return true
    end
  end
  return false
end

local function channelProcessor(text)
  if not Core.db.profile.shortChannelNames then return text end
  if isChannelNotice(text) then return text end

  text = text:gsub("|H(channel:.-)|h%[(.-)%]|h", function (data, name)
    local short = shortChannelName(data, name)
    if short then
      return "|H"..data.."|h["..short.."]|h"
    end
  end)

  -- Raid warnings are not links, only text at the start of the message
  local raidWarning = _G.CHAT_MSG_RAID_WARNING
  if raidWarning then
    local escaped = raidWarning:gsub("%p", "%%%0")
    text = text:gsub("^%["..escaped.."%]", "[RW]")
  end

  return text
end

---
-- The game marks the players of your Recent Allies list with a small yellow
-- person right after their name. That one becomes a Glass one (one person,
-- in the Glass gold). (The only icon the game puts right after a name: the
-- Discord, GM and mobile ones go before it, Timerunning's inside the name.)
local ALLY_ICON = "|TInterface\\AddOns\\Glass\\Glass\\Assets\\allyIcon:0:0:0:0:32:32:0:32:0:32:223:186:105|t"
local function allyProcessor(text)
  -- Most messages have no icon: nothing to look at then
  if not text:find("|Hplayer:", 1, true)
    or not (text:find("|A:", 1, true) or text:find("|T", 1, true)) then
    return text
  end
  text = text:gsub("(|Hplayer:[^|]*|h.-|h)(%s?)|A:[^|]*|a", "%1%2"..ALLY_ICON)
  text = text:gsub("(|Hplayer:[^|]*|h.-|h)(%s?)|T[^|]*|t", "%1%2"..ALLY_ICON)
  return text
end

---
-- Players' names (Messages options): their class and race icons in front of
-- them, and first names only ("Aehya" for "Aehya Bfc"; whispers still go to
-- the full name). A name in the chat is a link with the chat line it came
-- from, and the game tells who sent that line.
local RACE_ATLAS = {
  Scourge = "undead", LightforgedDraenei = "lightforged", DarkIronDwarf = "darkiron",
  HighmountainTauren = "highmountain", MagharOrc = "magharorc", ZandalariTroll = "zandalari",
  EarthenDwarf = "earthen", KulTiran = "kultiran",
}
local RACE_ICON = { Skyborne = 132845 } -- races with no race picture: an icon instead
local atlasMarkup = {} -- atlas -> markup, or false when the game doesn't have it

local function AtlasIcon(atlas, size)
  local key = atlas..size
  if atlasMarkup[key] == nil then
    local info = _G.C_Texture and _G.C_Texture.GetAtlasInfo and _G.C_Texture.GetAtlasInfo(atlas)
    atlasMarkup[key] = info and ("|A:"..atlas..":"..size..":"..size.."|a") or false
  end
  return atlasMarkup[key] or ""
end

local function SenderIcons(lineID, size)
  local profile = Core.db.profile
  local GetGUID = _G.C_ChatInfo and _G.C_ChatInfo.GetChatLineSenderGUID
  lineID = tonumber(lineID)
  if not (GetGUID and lineID and _G.GetPlayerInfoByGUID) then return "" end
  local ok, guid = pcall(GetGUID, lineID)
  if not ok or type(guid) ~= "string" or (issecretvalue and issecretvalue(guid)) or guid == "" then return "" end
  local ok2, _, class, _, race, sex = pcall(_G.GetPlayerInfoByGUID, guid)
  if not ok2 then return "" end
  local icons = ""
  if profile.chatRaceIcons and type(race) == "string" and not (issecretvalue and issecretvalue(race)) then
    local name = (RACE_ATLAS[race] or race:lower()).."-"..(sex == 3 and "female" or "male")
    local icon = AtlasIcon("raceicon128-"..name, size)
    if icon == "" then icon = AtlasIcon("raceicon-"..name, size) end
    -- Races the game has no race picture for (WoW Forever's Skyborne): an icon
    if icon == "" and RACE_ICON[race] then
      icon = "|T"..RACE_ICON[race]..":"..size..":"..size..":0:0:64:64:5:59:5:59|t"
    end
    icons = icons..icon
  end
  if profile.chatClassIcons and type(class) == "string" and not (issecretvalue and issecretvalue(class)) then
    icons = icons..AtlasIcon("classicon-"..class:lower(), size)
  end
  return icons ~= "" and (icons.." ") or ""
end

local function nameProcessor(text)
  local profile = Core.db.profile
  local icons = profile.chatClassIcons or profile.chatRaceIcons
  if not (icons or profile.firstNamesOnly) or not strfind(text, "|Hplayer:", 1, true) then return text end
  local size = math.floor((profile.messageFontSize or 14) + 0.5)
  return (text:gsub("(|Hplayer:([^|]*)|h)(.-)(|h)", function (open, data, shown, close)
    if profile.firstNamesOnly then
      -- The first word of the name, its color codes kept
      shown = shown:gsub("^(.-%a)%s+[^%s|%]]+", "%1", 1)
    end
    local prefix = icons and SenderIcons(data:match("^[^:]*:(%d+)"), size) or ""
    return prefix..open..shown..close
  end))
end

---
-- Emotes: ":)", ":D", "<3"... written as a word of their own become small
-- faces (Options > Messages > Emotes): outlines in the Glass gold, or classic
-- yellow faces. Only players with Glass see them; the others see the text.
local EMOTE_PATH = "Interface\\AddOns\\Glass\\Glass\\Assets\\Emotes\\"
local EMOTES = {
  [":)"] = "smile", [":-)"] = "smile",
  [":("] = "sad", [":-("] = "sad",
  [":D"] = "grin", [":-D"] = "grin",
  [";)"] = "wink", [";-)"] = "wink",
  [":P"] = "tongue", [":p"] = "tongue", [":-P"] = "tongue", [":-p"] = "tongue",
  [":O"] = "wow", [":o"] = "wow", [":-O"] = "wow", [":-o"] = "wow",
  -- (a typed "|" arrives doubled: it starts the game's text codes)
  [":||"] = "neutral", [":-||"] = "neutral",
  [":/"] = "meh", [":-/"] = "meh",
  ["xD"] = "laugh", ["XD"] = "laugh",
  ["<3"] = "heart",
  ["D:"] = "horror",
  [":S"] = "confused", [":s"] = "confused", [":-S"] = "confused", [":-s"] = "confused",
  [":*"] = "kiss", [":-*"] = "kiss",
  ["B)"] = "cool", ["B-)"] = "cool",
  [":'("] = "cry",
  [">:("] = "angry", [">:-("] = "angry",
}
-- The faces offered by the emote button of the chat box, with the code each
-- one writes (":|" isn't offered: a "|" written by an addon would start one of
-- the game's text codes)
TP.EMOTE_PICKS = {
  { "smile", ":)" }, { "grin", ":D" }, { "laugh", "xD" }, { "wink", ";)" },
  { "tongue", ":P" }, { "cool", "B)" }, { "kiss", ":*" }, { "heart", "<3" },
  { "wow", ":O" }, { "meh", ":/" }, { "confused", ":S" }, { "sad", ":(" },
  { "cry", ":'(" }, { "horror", "D:" }, { "angry", ">:(" },
}

-- A face's picture for the current style: file, then the tint (Glass gold)
function TP:EmoteTexture(name)
  local style = Core.db.profile.emoteStyle
  if style == "classic" then return EMOTE_PATH.."classic_"..name end
  return EMOTE_PATH.."glass_"..name, 223 / 255, 186 / 255, 105 / 255
end

local EMOTE_SCALE = 1.15 -- the faces are this much taller than the text
local emoteMarkup = { glass = {}, classic = {} } -- made once per face, style and size
local emoteStyle, emoteSize

local function EmoteMarkup(name)
  local cache = emoteMarkup[emoteStyle]
  local key = name..emoteSize
  if not cache[key] then
    local size = emoteSize..":"..emoteSize
    if emoteStyle == "glass" then
      cache[key] = "|T"..EMOTE_PATH.."glass_"..name..":"..size..":0:0:64:64:0:64:0:64:223:186:105|t"
    else
      cache[key] = "|T"..EMOTE_PATH.."classic_"..name..":"..size..":0:0:64:64:0:64:0:64|t"
    end
  end
  return cache[key]
end

local function emoteWord(word)
  local name = EMOTES[word]
  if name then return EmoteMarkup(name) end
  -- At the end of a sentence: ":)." or "<3!!"
  local core, trail = word:match("^(.-)([%.,!%?]+)$")
  name = core and EMOTES[core]
  if name then return EmoteMarkup(name)..trail end
end

local function emoteSegment(segment)
  return (segment:gsub("%S+", emoteWord))
end

local function emoteProcessor(text)
  emoteStyle = Core.db.profile.emoteStyle
  if emoteStyle ~= "glass" and emoteStyle ~= "classic" then return text end
  -- A quick look first: most messages have no emote
  if not (strfind(text, "[:;]'?%-?[%)%(DPpOoSs/|%*]") or strfind(text, "<3", 1, true)
    or strfind(text, "[xX]D") or strfind(text, "D:", 1, true) or strfind(text, "B%-?%)")) then
    return text
  end
  emoteSize = math.floor((Core.db.profile.messageFontSize or 14) * EMOTE_SCALE + 0.5)

  -- Only the text between links (items, players...): their names stay
  local parts = {}
  local cursor = 1
  while true do
    local mStart, mEnd = strfind(text, "|H.-|h.-|h", cursor)
    if not mStart then
      table.insert(parts, emoteSegment(strsub(text, cursor)))
      break
    end
    table.insert(parts, emoteSegment(strsub(text, cursor, mStart - 1)))
    table.insert(parts, strsub(text, mStart, mEnd))
    cursor = mEnd + 1
  end
  return table.concat(parts)
end

---
-- Timestamps (Messages > Timestamps): the time a message arrived, in a dim
-- color in front of it. It's a link: Shift+click writes the message in the
-- chat box (nothing is sent), a click opens it in the copy window. The texts
-- are kept for the last messages only.
local TIME_COLOR = "|cff8a8a8a"
local TIME_FORMATS = { hm = "%H:%M", hms = "%H:%M:%S" }
local TIME_KEEP = 600
local stampTexts, stampCount = {}, 0

function TP:Timestamp(t, text)
  local format = TIME_FORMATS[Core.db.profile.timestamps]
  if not format then return "" end
  stampCount = stampCount + 1
  stampTexts[stampCount] = text
  stampTexts[stampCount - TIME_KEEP] = nil
  return TIME_COLOR.."|Hglasstime:"..stampCount.."|h["..date(format, t).."]|h|r "
end

-- The message a timestamp belongs to, as plain text
function TP:StampText(id)
  local text = stampTexts[tonumber(id)]
  if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return nil end
  return Utils.PlainText(text)
end

-- The same in a whisper tab's name, where the game puts it first
function TP:AllyIconInTabName(text)
  if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return text end
  local swapped = text:gsub("^|A:[^|]*|a", ALLY_ICON):gsub("^|T[^|]*|t", function (icon)
    return icon == ALLY_ICON and icon or ALLY_ICON
  end)
  return swapped
end

---
-- Emotes in the separate windows too: those are the game's own chat windows,
-- so the faces go into the messages on their way there, through the game's
-- message filters. Only for windows out of the Glass chat (the Glass chat
-- adds them itself, see emoteProcessor).
local EMOTE_EVENTS = {
  "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER",
  "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
  "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
  "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER",
  "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_CHANNEL", "CHAT_MSG_COMMUNITIES_CHANNEL",
}

local function SeparateWindowEmotes(chatFrame, _, text, ...)
  if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return false end
  local ui = Core:GetModule("UIManager", true)
  if not (ui and ui.IsSeparateWindow and ui:IsSeparateWindow(chatFrame)) then return false end
  local ok, changed = pcall(emoteProcessor, text)
  if ok and changed ~= text then return false, changed, ... end
  return false
end

function TP:OnEnable()
  local AddFilter = (_G.ChatFrameUtil and _G.ChatFrameUtil.AddMessageEventFilter)
    or _G.ChatFrame_AddMessageEventFilter
  if not AddFilter then return end
  for _, event in ipairs(EMOTE_EVENTS) do
    AddFilter(event, SeparateWindowEmotes)
  end
end

---
-- Text processing pipeline
local TEXT_PROCESSORS = {
  nameProcessor,
  allyProcessor,
  emoteProcessor,
  textureProcessor,
  channelProcessor,
  urlProcessor,
  pratTimestampProcessor
}

function TP:ProcessText(text)
  local result = text

  for _, processor in ipairs(TEXT_PROCESSORS) do
    -- Prevent failing processors from bringing down the whole pipeline
    local retOk, retVal = pcall(processor, result)

    if retOk then
      result = retVal
    end
  end

  return result
end
