local Core = unpack(select(2, ...))
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
-- Text processing pipeline
local TEXT_PROCESSORS = {
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
