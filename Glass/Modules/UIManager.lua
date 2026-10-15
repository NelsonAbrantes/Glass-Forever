local Core, Constants, Utils = unpack(select(2, ...))
local UIManager = Core:GetModule("UIManager")

local CreateChatButtons = Core.Components.CreateChatButtons
local CreateChatDock = Core.Components.CreateChatDock
local CreateChatTab = Core.Components.CreateChatTab
local CreateEditBox = Core.Components.CreateEditBox
local CreateMainContainerFrame = Core.Components.CreateMainContainerFrame
local CreateMoverDialog = Core.Components.CreateMoverDialog
local CreateMoverFrame = Core.Components.CreateMoverFrame
local CreateSlidingMessageFramePool = Core.Components.CreateSlidingMessageFramePool

-- luacheck: push ignore 113
local BNToastFrame = BNToastFrame
local ChatAlertFrame = ChatAlertFrame
local CreateFrame = CreateFrame
local FCFDock_GetSelectedWindow = FCFDock_GetSelectedWindow
local FCF_RestorePositionAndDimensions = FCF_RestorePositionAndDimensions
local GENERAL_CHAT_DOCK = GENERAL_CHAT_DOCK
local GetChatWindowInfo = GetChatWindowInfo
local GetCVar = C_CVar and C_CVar.GetCVar or GetCVar
local NUM_CHAT_WINDOWS = NUM_CHAT_WINDOWS
local SetCVar = C_CVar and C_CVar.SetCVar or SetCVar
local UIParent = UIParent
-- luacheck: pop

local TABS_CHECK_EVERY = 0.03 -- seconds between checks of the selected tab

----
-- UIManager Module
function UIManager:OnInitialize()
  self.state = {
    frames = {},
    tabs = {},
    temporaryFrames = {},
    temporaryTabs = {}
  }
end

function UIManager:OnEnable()
  self.tickerFrame = CreateFrame("Frame", "GlassUpdaterFrame", UIParent)

  -- Mover
  self.moverFrame = CreateMoverFrame("GlassMoverFrame", UIParent)
  self.moverDialog = CreateMoverDialog("GlassMoverDialog", UIParent)

  -- Main Container
  self.container = CreateMainContainerFrame("GlassFrame", UIParent)
  self.container:SetPoint("TOPLEFT", self.moverFrame)

  -- Chat dock
  self.dock = CreateChatDock(self.container)

  -- SlidingMessageFrames
  self.slidingMessageFramePool = CreateSlidingMessageFramePool(self.container)

  for i=1, NUM_CHAT_WINDOWS do
    local chatFrame = _G["ChatFrame"..i]
    local smf = self.slidingMessageFramePool:Acquire()
    smf:Init(chatFrame)

    self.state.frames[i] = smf
    self.state.tabs[i] = CreateChatTab(smf)
  end

  -- Windows left undocked last time stay separate chat windows. The game
  -- loads the window settings (open, docked...) a while after login and says
  -- so with UPDATE_CHAT_WINDOWS, so this runs then too; it skips windows
  -- that are already separate.
  --
  -- The game can't tell which windows are open: it says "closed" for any
  -- window that's hidden, and Glass hides them all while loading. So Glass
  -- remembers its separate windows itself.
  -- ...and which of them are minimized
  local function RememberMinimized(chatFrame, minimized)
    if not chatFrame or chatFrame.isTemporary then return end
    Core.db.char.minimizedWindows = Core.db.char.minimizedWindows or {}
    Core.db.char.minimizedWindows[chatFrame:GetName()] = minimized or nil
  end

  local function RememberSeparate(chatFrame, separate)
    if not chatFrame or chatFrame.isTemporary then return end
    Core.db.char.separateWindows = Core.db.char.separateWindows or {}
    Core.db.char.separateWindows[chatFrame:GetName()] = separate or nil
    if not separate then
      RememberMinimized(chatFrame, false)
    end
  end

  local function RestoreSeparateWindows()
    local remembered = Core.db.char.separateWindows or {}
    for i, smf in ipairs(self.state.frames) do
      local chatFrame = smf.chatFrame
      local shown = remembered[chatFrame:GetName()] or select(7, GetChatWindowInfo(i))
      local docked = chatFrame.isDocked or select(9, GetChatWindowInfo(i))
      if shown and not docked and smf.state
        and not smf.state.isCombatLog and not smf.state.detached then
        smf:ReleaseChatFrame()
        if FCF_RestorePositionAndDimensions then
          FCF_RestorePositionAndDimensions(chatFrame)
        end
        -- Our copy of where it was while separate (see the
        -- FCF_SavePositionAndDimensions hook)
        local saved = Core.db.char.windowPositions and Core.db.char.windowPositions[chatFrame:GetName()]
        if saved then
          local point, x, y = unpack(saved)
          chatFrame:ClearAllPoints()
          chatFrame:SetPoint(point, x * _G.GetScreenWidth(), y * _G.GetScreenHeight())
          _G.SetChatWindowSavedPosition(chatFrame:GetID(), point, x, y)
        end
        chatFrame:Show()
        _G.SetChatWindowShown(chatFrame:GetID(), true)

        -- It was minimized last time (the game doesn't remember that)
        local minimized = Core.db.char.minimizedWindows
        if minimized and minimized[chatFrame:GetName()] and _G.FCF_MinimizeFrame then
          _G.FCF_MinimizeFrame(chatFrame, (chatFrame.buttonSide or "left"):upper())
        end
      end
    end
  end

  self.tickerFrame:RegisterEvent("UPDATE_CHAT_WINDOWS")
  self.tickerFrame:HookScript("OnEvent", function (_, event)
    if event == "UPDATE_CHAT_WINDOWS" then
      -- After the game's own handling of the event
      C_Timer.After(0, RestoreSeparateWindows)
    end
  end)

  -- Show the main chat panel on login (after the game has finished loading)
  C_Timer.After(1, function()
    local main = self.state.frames[1]
    if main then
      main:Show()
    end
    RestoreSeparateWindows()
  end)

  -- Dragging a tab out of the dock makes it a normal chat window; dragging it
  -- back gives it to Glass again
  local function FindFrame(chatFrame)
    if not chatFrame then return nil end
    for _, smf in ipairs(self.state.frames) do
      if smf.chatFrame == chatFrame then return smf end
    end
    -- Temporary windows (whispers)
    local name = chatFrame.GetName and chatFrame:GetName()
    return name and self.state.temporaryFrames[name]
  end

  -- True if the window is still in use and meant to be visible, i.e. it was
  -- undocked rather than closed (closing a window also undocks it)
  local function StillOpen(smf, chatFrame)
    if chatFrame.isDocked or not smf.state.detached then return false end
    if chatFrame.isTemporary then
      return self.state.temporaryFrames[chatFrame:GetName()] == smf
    end
    return select(7, GetChatWindowInfo(chatFrame:GetID())) and true or false
  end

  self:SecureHook("FCF_UnDockFrame", function (chatFrame)
    local smf = FindFrame(chatFrame)
    if not smf or not smf.state or smf.state.isCombatLog or smf.state.detached then return end

    smf:ReleaseChatFrame()

    -- Wait a moment: if the game is closing the window, it's gone by then
    C_Timer.After(0, function ()
      if StillOpen(smf, chatFrame) then
        chatFrame:Show()
        RememberSeparate(chatFrame, true)
      end
    end)
  end)

  -- The game saves a window's position when it's docked again too, after
  -- Glass has moved it into the chat; it would come back there after a reload.
  -- Keep our own copy of the last position the window had while separate.
  if _G.FCF_SavePositionAndDimensions then
    self:SecureHook("FCF_SavePositionAndDimensions", function (chatFrame)
      local smf = FindFrame(chatFrame)
      if smf and smf.state and smf.state.detached and not chatFrame.isTemporary then
        local point, x, y = _G.GetChatWindowSavedPosition(chatFrame:GetID())
        if point then
          Core.db.char.windowPositions = Core.db.char.windowPositions or {}
          Core.db.char.windowPositions[chatFrame:GetName()] = { point, x, y }
        end
      end
    end)
  end

  -- Minimizing a separate window shows a bar with its name: Glass look too
  if _G.FCF_MinimizeFrame then
    self:SecureHook("FCF_MinimizeFrame", function (chatFrame)
      local smf = FindFrame(chatFrame)
      if smf and smf.state and smf.state.detached then
        smf:StyleMinimizedFrame()
        RememberMinimized(chatFrame, true)
      end
    end)
  end
  if _G.FCF_MaximizeFrame then
    self:SecureHook("FCF_MaximizeFrame", function (chatFrame)
      RememberMinimized(chatFrame, false)
    end)
  end

  -- Changing the font size from the tab menu resets the font, put Glass' back
  if _G.FCF_SetChatWindowFontSize then
    self:SecureHook("FCF_SetChatWindowFontSize", function (_, chatFrame)
      local smf = FindFrame(chatFrame or _G.FCF_GetCurrentChatFrame and _G.FCF_GetCurrentChatFrame())
      if smf then smf:ApplyGlassFont() end
    end)
  end

  -- Shows the messages of the tab the game has selected, and hides the others
  local function ShowSelectedFrame()
    local selected = FCFDock_GetSelectedWindow and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
    if not selected then return end
    local function Sync(smf)
      if smf.state and not smf.state.detached and not smf.state.isCombatLog then
        if smf.chatFrame == selected then smf:Show() else smf:Hide() end
      end
    end
    for _, smf in ipairs(self.state.frames) do Sync(smf) end
    for _, smf in pairs(self.state.temporaryFrames) do Sync(smf) end
  end

  self:SecureHook("FCF_DockFrame", function (chatFrame)
    RememberSeparate(chatFrame, false)
    local smf = FindFrame(chatFrame)
    if smf and smf.state and smf.state.detached then
      smf:TakeOverChatFrame()
      -- The game selects the window docked again, but Glass was still showing
      -- the tab that was open before (after the game is done with the dock)
      C_Timer.After(0, ShowSelectedFrame)
    end
  end)

  -- Edit box
  self.editBox = CreateEditBox(self.container)

  -- Fix Battle.net Toast frame position
  BNToastFrame:ClearAllPoints()
  BNToastFrame:SetPoint("BOTTOMLEFT", ChatAlertFrame, "BOTTOMLEFT", 0, 0)

  ChatAlertFrame:ClearAllPoints()
  ChatAlertFrame:SetPoint("BOTTOMLEFT", self.container, "TOPLEFT", 15, 10)

  -- The game's chat buttons (social, channels, voice, menu): hidden, or beside
  -- the chat with the "Chat buttons" option
  self.chatButtons = CreateChatButtons(self.container)
  self.container.chatButtons = self.chatButtons

  -- New version alert
  --@non-debug@
  -- Any change counts, not only a higher number: the fork restarted its
  -- numbering at 0.9.x after the first beta was released as 1.9.0-forever1.
  if Core.db.global.version ~= Core.Version then
    Utils.notify('Glass Forever has just been updated. |cFFFFFF00|Hgarrmission:Glass:opennews|h[See what’s new]|h|r')
    Core.db.global.version = Core.Version
  end
  --@end-non-debug@--

  -- Force classic chat style
  if GetCVar("chatStyle") ~= "classic" then
    SetCVar("chatStyle", "classic")
    Utils.notify('Chat Style set to "Classic Style"')

    -- Resets the background that IM style causes
    self.editBox:SetFocus()
    self.editBox:ClearFocus()
  end

  -- Handle temporary chat frames (whisper popout, pet battle)
  -- Secure hooks (run after the game's code): replacing these functions would
  -- taint the game's chat code, which a new whisper runs through, and it then
  -- fails on "secret" messages. A secure hook doesn't get the new window, so
  -- look for open temporary windows Glass doesn't have yet.
  self:SecureHook("FCF_OpenTemporaryWindow", function ()
    for _, name in ipairs(_G.CHAT_FRAMES or {}) do
      local chatFrame = _G[name]
      if chatFrame and chatFrame.isTemporary and (chatFrame.isDocked or chatFrame.inUse)
        and not self.state.temporaryFrames[name] then
        local smf = self.slidingMessageFramePool:Acquire()
        smf:Init(chatFrame)

        self.state.temporaryFrames[name] = smf
        self.state.temporaryTabs[name] = CreateChatTab(smf)
      end
    end
  end)

  -- Close window
  self:SecureHook("FCF_Close", function (chatFrame)
    RememberSeparate(chatFrame, false)
    local name = chatFrame and chatFrame:GetName()
    local smf = name and self.state.temporaryFrames[name]
    if smf then
      self.slidingMessageFramePool:Release(smf)
      self.state.temporaryFrames[name] = nil
      self.state.temporaryTabs[name] = nil
    end
  end)

  -- Light up a tab when a message of one of its chat types arrives and the tab
  -- is not selected. The glow takes the color of the chat type (guild green,
  -- party blue, etc). Blizzard only flashes tabs for whispers by default, see
  -- the FCF_StartAlertFlash hook below for those.
  -- The color itself is applied in ChatTab.lua through tab.glowColor.
  local ALERT_SECONDS = 10 -- how long the dock stays visible after a message
  -- Only the chats meant for you and your groups: say, yell and emotes from
  -- anyone nearby lit tabs (white) all the time
  local ALERT_EVENTS = {
    CHAT_MSG_GUILD = "GUILD",
    CHAT_MSG_OFFICER = "OFFICER",
    CHAT_MSG_PARTY = "PARTY",
    CHAT_MSG_PARTY_LEADER = "PARTY",
    CHAT_MSG_RAID = "RAID",
    CHAT_MSG_RAID_LEADER = "RAID",
    CHAT_MSG_RAID_WARNING = "RAID_WARNING",
    CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
  }

  -- Reveal the dock (the tab bar) so a glowing tab is visible, then let it
  -- fade out again after a few seconds
  local function RevealDock()
    if self.dock and not self.container.state.mouseOver then
      self.dock:Show()
      if Core.db.profile.tabBarFade ~= false then
        self.dock:HideDelay(ALERT_SECONDS)
      end
    end
  end

  local function TabHasGroup(chatFrame, group)
    for _, g in ipairs(chatFrame.messageTypeList or {}) do
      if g == group then return true end
    end
    return false
  end

  local alertFrame = CreateFrame("Frame")
  for event in pairs(ALERT_EVENTS) do
    alertFrame:RegisterEvent(event)
  end
  alertFrame:SetScript("OnEvent", function (_, event)
    -- Turned off in the Tabs options
    if not Core.db.profile.tabAlerts then return end

    local group = ALERT_EVENTS[event]
    -- Color of the specific type (e.g. PARTY_LEADER), falling back to the group
    local info = ChatTypeInfo and (ChatTypeInfo[strsub(event, 10)] or ChatTypeInfo[group])
    if not info then return end

    local alerted = false
    -- Skip ChatFrame1 (General, receives everything) and ChatFrame2 (combat log)
    for i = 3, NUM_CHAT_WINDOWS do
      local chatFrame = _G["ChatFrame"..i]
      local tab = _G["ChatFrame"..i.."Tab"]
      if chatFrame and tab and tab.glow
        and not chatFrame.isTemporary
        and chatFrame ~= _G.SELECTED_CHAT_FRAME
        and TabHasGroup(chatFrame, group) then
        tab.glowColor = info
        tab.glow:Show()
        alerted = true
      end
    end

    if alerted then
      RevealDock()
    end
  end)


  -- Whispers: the game itself flashes the right tab (the whisper tab of that
  -- person, or a tab that shows whispers). Give that glow the whisper color and
  -- reveal the dock, like the other chat types above.
  if _G.FCF_StartAlertFlash then
    self:SecureHook("FCF_StartAlertFlash", function (chatFrame)
      if not chatFrame or not chatFrame.isDocked then return end

      -- Turned off in the Tabs options: undo the game's own flash too
      if not Core.db.profile.tabAlerts then
        local tab = _G[chatFrame:GetName().."Tab"]
        if tab and tab.glow then
          if _G.UIFrameFlashStop then _G.UIFrameFlashStop(tab.glow) end
          tab.glow:Hide()
        end
        return
      end

      -- Glass hides the game's chat frames, so the game flashes even the tab
      -- being shown. Skip that one.
      local smf = FindFrame(chatFrame)
      if smf and smf:IsVisible() then return end

      local tab = _G[chatFrame:GetName().."Tab"]
      local info = ChatTypeInfo and (ChatTypeInfo[chatFrame.chatType or "WHISPER"] or ChatTypeInfo.WHISPER)
      -- The game makes the glow flash, which ends up invisible here. Use a
      -- steady glow instead, the same as for the other chat types.
      if tab and info and tab.glow and tab.ShowSteadyGlow then
        tab:ShowSteadyGlow(info)
      end

      RevealDock()
    end)
  end

  -- Keep the default Blizzard chat frame hidden behind Glass. Some code paths
  -- (e.g. creating a new tab) show it without going through our Show hook,
  -- which made messages appear twice. HideChatFrame leaves the Glass panel
  -- itself alone.
  local function HideBlizzardFrame(smf)
    local chatFrame = smf.chatFrame
    if smf.state and smf.state.detached then return end -- a separate window, leave it
    if chatFrame and chatFrame:IsShown() and smf.HideChatFrame then
      smf:HideChatFrame()
    end
  end

  -- A separate window with the Glass look brings its faded messages back
  -- while the mouse is over it, like the Glass chat (the game only does that
  -- when scrolling). Again before they would fade, so they stay while the
  -- mouse does.
  -- Redrawing the window as a link is clicked lost the click (the tooltip
  -- didn't open): it's done as seldom as possible, just before the messages
  -- would fade, and never while a mouse button is held down.
  local function RevealWindow(smf, now)
    local chatFrame = smf.chatFrame
    if not (smf.state and smf.state.detached and chatFrame and chatFrame.ResetAllFadeTimes) then return end
    if chatFrame:IsVisible() and chatFrame:IsMouseOver() and smf:UsesWindowStyle() then
      local every = math.max(2, (Core.db.profile.chatHoldTime or 10) - 1)
      if (not smf.revealedAt or now - smf.revealedAt >= every)
        and not IsMouseButtonDown("LeftButton") and not IsMouseButtonDown("RightButton") then
        smf.revealedAt = now
        chatFrame:ResetAllFadeTimes()
        -- That only marks the window to be drawn again, which happens when
        -- it next updates: only now and then while nothing new comes in
        if chatFrame.RefreshIfNecessary then
          chatFrame:RefreshIfNecessary()
        elseif chatFrame.RefreshDisplay then
          chatFrame:RefreshDisplay()
        end
      end
    else
      smf.revealedAt = nil
    end
  end

  -- Start rendering
  self.timeElapsed = 0
  self.tickerFrame:SetScript("OnUpdate", function (_, elapsed)
    for _, smf in pairs(self.state.frames) do
      if smf.state and not smf.state.isCombatLog then
        HideBlizzardFrame(smf)
      end
    end
    for _, smf in pairs(self.state.temporaryFrames) do
      HideBlizzardFrame(smf)
    end

    -- Show the panel of the selected tab and hide all the others. Use the tab
    -- selected in the Glass dock: clicking a separate window changes
    -- SELECTED_CHAT_FRAME but shouldn't empty Glass. About 30 times a
    -- second, which feels instant; every frame only while the selected line
    -- slides to another tab.
    self.tabsElapsed = (self.tabsElapsed or 0) + elapsed
    local tabsDue = self.tabsElapsed >= TABS_CHECK_EVERY
      or (Core.Components.TabLineMoving and Core.Components.TabLineMoving())
      or (Core.Components.TabAlerting and Core.Components.TabAlerting())
    local selected = _G.SELECTED_CHAT_FRAME
    if FCFDock_GetSelectedWindow and GENERAL_CHAT_DOCK then
      selected = FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK) or selected
    end
    -- (its own clock: the tabs' one restarts every frame while a tab alerts)
    self.revealElapsed = (self.revealElapsed or 0) + elapsed
    if self.revealElapsed >= TABS_CHECK_EVERY then
      self.revealElapsed = 0
      local now = GetTime()
      for _, smf in pairs(self.state.frames) do RevealWindow(smf, now) end
      for _, smf in pairs(self.state.temporaryFrames) do RevealWindow(smf, now) end
    end
    -- A newly selected tab shows its messages right away
    if selected ~= self.lastSelected then
      self.lastSelected = selected
      tabsDue = true
    end
    if tabsDue then self.tabsElapsed = 0 end
    if selected and tabsDue then
      for _, smf in pairs(self.state.frames) do
        if smf.chatFrame and smf.state and not smf.state.isCombatLog and not smf.state.detached then
          if smf.chatFrame == selected then
            if not smf:IsShown() then smf:Show() end
          elseif smf:IsShown() then
            smf:Hide()
          end
        end
      end
      for _, smf in pairs(self.state.temporaryFrames) do
        if smf.state and smf.state.detached then
          -- A separate window, the game shows it
        elseif smf.chatFrame == selected then
          if not smf:IsShown() then smf:Show() end
        elseif smf:IsShown() then
          smf:Hide()
        end
      end

      -- Draw the "selected" line above the active tab
      for _, tab in pairs(self.state.tabs) do
        if tab.UpdateSelected then tab:UpdateSelected(selected) end
      end
      for _, tab in pairs(self.state.temporaryTabs) do
        if tab.UpdateSelected then tab:UpdateSelected(selected) end
      end
    end

    -- At most once per frame (and at most 100 times a second). This used to
    -- repeat to "catch up" after a slow frame, e.g. 30 times after a 0.3s
    -- loading hitch, which made the hitch worse. OnFrame only handles queued
    -- messages and mouse over, so once is enough.
    self.timeElapsed = self.timeElapsed + elapsed

    if self.timeElapsed >= 0.01 then
      self.timeElapsed = 0

      self.container:OnFrame()

      for _, smf in ipairs(self.state.frames) do
        smf:OnFrame()
      end

      for _, smf in pairs(self.state.temporaryFrames) do
        smf:OnFrame()
      end
    end
  end)
end
