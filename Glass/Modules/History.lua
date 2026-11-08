local Core, Constants = unpack(select(2, ...))
local History = Core:GetModule("History")

-- luacheck: push ignore 113
local C_Timer = C_Timer
local date = date
local time = time
-- luacheck: pop

local MAX_LINES = 50 -- messages kept per tab
local MAX_WHISPER_TABS = 20 -- whisper tabs kept with their messages

-- Saved whisper tabs not open yet (lower-case name -> { target, lines, fill }),
-- see Restore
local pendingWhispers = {}

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

-- The newest messages of a tab, as saved
local function Lines(smf)
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
  return CleanUp(lines)
end

local function Save()
  local history = {}
  local whisperTabs = {}
  local total = 0

  if Core.db.profile.keepHistory ~= false then
    for _, smf in pairs(GetFrames()) do
      local chatFrame = smf.chatFrame
      if chatFrame and smf.state and not smf.state.isCombatLog then
        local lines = Lines(smf)
        if #lines > 0 then
          history[chatFrame:GetName()] = lines
          total = total + #lines
        end
      end
    end

    -- Whisper tabs: the game forgets them, so they'd vanish with what was
    -- said. Kept until they're closed. (Battle.net whispers can't be: their
    -- names change every session.)
    for _, smf in pairs(Core:GetModule("UIManager").state.temporaryFrames) do
      local chatFrame = smf.chatFrame
      local target = chatFrame and chatFrame.chatTarget
      if chatFrame and smf.state and chatFrame.chatType == "WHISPER" and type(target) == "string"
        and not (issecretvalue and issecretvalue(target)) and target ~= "" then
        local lines = Lines(smf)
        table.insert(whisperTabs, { target = chatFrame.chatTarget, lines = lines })
        total = total + #lines
      end
    end

    -- And the saved ones whose tab didn't open this session (no whisper with
    -- that person yet), up to MAX_WHISPER_TABS in all
    for _, pending in pairs(pendingWhispers) do
      if #whisperTabs >= MAX_WHISPER_TABS then break end
      -- (with when they were said, for the separator)
      table.insert(whisperTabs, { target = pending.target, lines = pending.lines, savedAt = pending.savedAt })
      total = total + #pending.lines
    end
  end

  Core.db.char.history = history
  Core.db.char.whisperTabs = whisperTabs
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

-- The open Glass tab of a whisper with this person, if any
local function FindWhisperTab(target)
  for _, smf in pairs(Core:GetModule("UIManager").state.temporaryFrames) do
    local chatFrame = smf.chatFrame
    local chatTarget = chatFrame and chatFrame.chatTarget
    if chatFrame and chatFrame.chatType == "WHISPER" and type(chatTarget) == "string"
      and not (issecretvalue and issecretvalue(chatTarget))
      and chatTarget:lower() == target:lower() then
      return smf
    end
  end
end

local function Restore()
  local history = Core.db.char.history
  if not history or Core.db.profile.keepHistory == false then return end

  local savedAt = Core.db.char.historySavedAt
  local separator = savedAt
    and string.format(SEPARATOR, date("%d %b, %H:%M", savedAt))
    or string.format(SEPARATOR, "earlier")

  -- Back-filled messages are stacked on top of the current ones, so they're
  -- added newest first to keep the original order. The separator goes first:
  -- it ends up between the old messages and the new ones. It is saved with
  -- the messages, so each earlier session keeps its own.
  local function Fill(smf, lines, tabSavedAt)
    local separator = tabSavedAt
      and string.format(SEPARATOR, date("%d %b, %H:%M", tabSavedAt)) or separator
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

  for _, smf in pairs(GetFrames()) do
    local chatFrame = smf.chatFrame
    local lines = chatFrame and history[chatFrame:GetName()]
    -- Also tidies history saved by earlier versions, which piled up
    -- separators in tabs with no messages
    lines = lines and CleanUp(lines)
    if lines and #lines > 0 and smf.state and not smf.state.didBackfill and not AlreadyShown(smf, lines) then
      Fill(smf, lines)
    end
  end

  -- The whisper tabs that were open: their messages come back when the game
  -- opens the tab again (a whisper from or to that person). Glass no longer
  -- opens them itself: a whisper window opened by an addon is "tainted", and
  -- the next whisper in it made the game's chat code fail (an error blamed on
  -- Glass).
  local whisperTabs = Core.db.char.whisperTabs
  if not whisperTabs then return end
  wipe(pendingWhispers)
  for _, tab in ipairs(whisperTabs) do
    if type(tab.target) == "string" and tab.target ~= "" then
      local lines = tab.lines and CleanUp(tab.lines)
      if lines and #lines > 0 then
        local smf = FindWhisperTab(tab.target)
        if smf then
          if smf.state and not AlreadyShown(smf, lines) then Fill(smf, lines, tab.savedAt) end
        else
          pendingWhispers[tab.target:lower()] = {
            target = tab.target, lines = lines, fill = Fill, savedAt = tab.savedAt or savedAt,
          }
        end
      end
    end
  end
end

-- The game opened a whisper tab: the messages saved for that person
local function WhisperTabOpened(chatType, chatTarget)
  if chatType ~= "WHISPER" or type(chatTarget) ~= "string" then return end
  if issecretvalue and issecretvalue(chatTarget) then return end
  local key = chatTarget:lower()
  if not pendingWhispers[key] then return end
  -- (a moment later: the Glass tab is made after the game's)
  C_Timer.After(0, function ()
    local pending = pendingWhispers[key]
    local smf = pending and FindWhisperTab(pending.target)
    if not smf or not smf.state then return end
    pendingWhispers[key] = nil
    if not AlreadyShown(smf, pending.lines) then pending.fill(smf, pending.lines, pending.savedAt) end
  end)
end

function History:OnEnable()
  -- AceDB fires this on logout before it strips default values, so the
  -- settings still read correctly here
  Core.db.RegisterCallback(self, "OnDatabaseShutdown", SafeSave)

  -- Remove a note left by a test version
  Core.db.global.historyDebug = nil

  -- Wait a moment so the game can restore its own messages first
  C_Timer.After(2, Restore)

  if _G.FCF_OpenTemporaryWindow then
    hooksecurefunc("FCF_OpenTemporaryWindow", WhisperTabOpened)
  end
end
