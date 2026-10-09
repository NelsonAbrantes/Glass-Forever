local Core = unpack(select(2, ...))
local History = Core:GetModule("History")

-- luacheck: push ignore 113
local C_Timer = C_Timer
-- luacheck: pop

local MAX_LINES = 50 -- messages kept per tab

----
-- History Module
--
-- Saves the last messages of each tab when you log out (or /reload), per
-- character, and shows them again when you log back in. If the game restores
-- old messages by itself, the saved ones are not added, to avoid duplicates.

local function GetFrames()
  return Core:GetModule("UIManager").state.frames
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
            table.insert(lines, { raw.text, raw.r, raw.g, raw.b })
          end
        end

        -- Keep only the newest lines
        while #lines > MAX_LINES do
          table.remove(lines, 1)
        end

        if #lines > 0 then
          history[chatFrame:GetName()] = lines
          total = total + #lines
        end
      end
    end
  end

  Core.db.char.history = history
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

local function Restore()
  local history = Core.db.char.history
  if not history or Core.db.profile.keepHistory == false then return end

  for _, smf in pairs(GetFrames()) do
    local chatFrame = smf.chatFrame
    local lines = chatFrame and history[chatFrame:GetName()]
    if lines and smf.state and not smf.state.didBackfill and not AlreadyShown(smf, lines) then
      -- Back-filled messages are stacked on top of the current ones, so
      -- add them newest first to keep the original order
      for i = #lines, 1, -1 do
        local line = lines[i]
        smf:BackFillMessage(nil, line[1], line[2], line[3], line[4])
      end
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
