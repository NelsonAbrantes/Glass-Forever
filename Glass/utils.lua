local Core, _, Utils = unpack(select(2, ...))

local map = Core.Libs.lodash.map

-- luacheck: push ignore 113
local strsplit = strsplit
-- luacheck: pop

-- Utility functions

---
-- Height of the tab bar and space around each tab name (Tabs options)
Utils.TabBarHeight = function ()
  return Core.db.profile.tabBarHeight or 20
end

Utils.TabPadding = function ()
  return Core.db.profile.tabPadding or 15
end

-- True when the tab bar is below the messages (Tabs options)
Utils.TabBarAtBottom = function ()
  return Core.db.profile.tabBarPosition == "bottom"
end

Utils.super = function (obj)
  return getmetatable(obj).__index
end

---
-- Print to VDT
Utils.print = function (str, t)
  if _G.ViragDevTool_AddData then
    _G.ViragDevTool_AddData(t, str)
  else
    -- Buffer print messages until ViragDevTool loads
    table.insert(Core.printBuffer, {str, t})
  end
end

---
-- Prints Glass' notification messages
Utils.notify = function (message)
  print("|c00DFBA69Glass Forever|r: ", message)
end

---
-- Returns true if version is newer
Utils.versionGreaterThan = function (current, previous)
  local cur = {strsplit('.', current)}
  local prev = {strsplit('.', previous)}

  local curPre = {strsplit('-', cur[3])}
  local prevPre = {strsplit('-', prev[3])}

  cur[3] = curPre[1]
  prev[3] = prevPre[1]

  cur = map(cur, function (v) return tonumber(v) end)
  prev = map(prev, function (v) return tonumber(v) end)

  if cur[1] > prev[1] then
    return true
  end

  if cur[2] > prev[2] then
    return true
  end

  if cur[3] > prev[3] then
    return true
  end

  -- Previous was a prerelease
  if #curPre ~= 2 and #prevPre == 2 then
    return true
  end

  return false
end
