local Core, Constants = unpack(select(2, ...))
local History = Core:GetModule("History")

-- luacheck: push ignore 113
local C_Timer = C_Timer
local date = date
local time = time
-- luacheck: pop

local MAX_LINES = 50 -- messages kept per tab

-- Line shown under the restored messages, so they aren't mixed up with the
-- ones from this session. The chat draws it with lines on each side, as
-- "Previous session · 12 Oct, 14:30" (MessageLine.lua).
local SEPARATOR = "Previous session, ended %s"
local SEPARATOR_COLOR = 0.5 -- gray (the chat shows it in a dim gold)

----
-- History Module
--
-- Saves the last messages of each tab when you log out (or /reload), per
-- character, and shows them again when you log back in. If the game restores
-- old messages by itself, the saved ones are not added, to avoid duplicates.

local function GetFrames()
  return Core:GetModule("UIManager").state.frames
end

-- (also the "-------- ... --------" ones saved by earlier versions)
local function IsSeparator(line)
  return Core.Components.SeparatorText(line[1]) ~= nil
end

-- Keeps only the separators that sit between messages: none at the start or
-- the end, and one where several follow each other (sessions with no new
-- messages in that tab). The first one is kept: it marks when the messages
-- above it were said.
local function CleanUp(lines)
  local cleaned = {}
  local hasMessages = false
  local pending
  for _, line in ipairs(lines) do
    if IsSeparator(line) then
      if hasMessages and not pending then
        pending = line
      end
    else
      if pending then
        table.insert(cleaned, pending)
        pending = nil
      end
      table.insert(cleaned, line)
      hasMessages = true
    end
  end
  return cleaned
end

local function Save()
  local history = {}
  local total = 0

  if Core.db.profile.keepHistory ~= false then
    for _, smf in pairs(GetFrames()) do
      local chatFrame = smf.chatFrame
      if chatFrame and smf.state and not smf.state.isCombatLog then
        local lines = {}
        for _, message in ipairs(smf.state.messages) do
          local raw = message.raw
          -- Text the game marks as secret can't be saved
          if raw and type(raw.text) == "string"
            and not (issecretvalue and issecretvalue(raw.text)) then
            -- (with the time it arrived, for Timestamps)
            table.insert(lines, { raw.text, raw.r, raw.g, raw.b, message.glassTime })
          end
        end

        -- Keep only the newest lines
        lines = CleanUp(lines)
        while #lines > MAX_LINES do
          table.remove(lines, 1)
        end
        lines = CleanUp(lines)

        if #lines > 0 then
          history[chatFrame:GetName()] = lines
          total = total + #lines
        end
      end
    end
  end

  Core.db.char.history = history
  Core.db.char.historySavedAt = time()
  return total
end

-- An error while logging out would go unnoticed and could stop other addons
-- from saving, so keep it contained
local function SafeSave()
  pcall(Save)
end

-- True if the game already brought back these messages (e.g. after /reload):
-- most of the newest saved lines are already in the tab.
local function AlreadyShown(smf, lines)
  local current = {}
  for _, message in ipairs(smf.state.messages) do
    local text = message.raw and message.raw.text
    if type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
      current[text] = true
    end
  end

  local checked, found = 0, 0
  for i = #lines, math.max(1, #lines - 4), -1 do
    checked = checked + 1
    if current[lines[i][1]] then found = found + 1 end
  end

  return found > 0 and found >= math.min(3, checked)
end

-- The separator in a separate window: its text in the dim gold. The window
-- draws it like the chat does, between two fading lines
-- (SlidingMessageFrame:DrawWindowSeparators).
local function WindowSeparator(separator)
  local gold = Constants.COLORS.apache
  local text = Core.Components.SeparatorText(separator) or separator
  return {
    text,
    gold.r * 0.85, gold.g * 0.85, gold.b * 0.85,
  }
end

local function Restore()
  local history = Core.db.char.history
  if not history or Core.db.profile.keepHistory == false then return end

  local savedAt = Core.db.char.historySavedAt
  local separator = savedAt
    and string.format(SEPARATOR, date("%d %b, %H:%M", savedAt))
    or string.format(SEPARATOR, "earlier")

  for _, smf in pairs(GetFrames()) do
    local chatFrame = smf.chatFrame
    local lines = chatFrame and history[chatFrame:GetName()]
    -- Also tidies history saved by earlier versions, which piled up
    -- separators in tabs with no messages
    lines = lines and CleanUp(lines)
    if lines and #lines > 0 and smf.state and not smf.state.didBackfill and not AlreadyShown(smf, lines) then
      -- Back-filled messages are stacked on top of the current ones, so
      -- add them newest first to keep the original order. The separator
      -- goes first: it ends up between the old messages and the new ones.
      -- It is saved with the messages, so each earlier session keeps its own.
      smf:BackFillMessage(nil, separator, SEPARATOR_COLOR, SEPARATOR_COLOR, SEPARATOR_COLOR)
      local window = { WindowSeparator(separator) }
      for i = #lines, 1, -1 do
        local line = lines[i]
        smf:BackFillMessageAt(line[5], nil, line[1], line[2], line[3], line[4])
        table.insert(window, line)
      end
      -- Also in the game's window, shown when the tab is a separate window
      smf:BackFillWindow(window)
    end
  end
end

function History:OnEnable()
  -- AceDB fires this on logout before it strips default values, so the
  -- settings still read correctly here
  Core.db.RegisterCallback(self, "OnDatabaseShutdown", SafeSave)

  -- Remove a note left by a test version
  Core.db.global.historyDebug = nil

  -- Wait a moment so the game can restore its own messages first
  C_Timer.After(2, Restore)
end
