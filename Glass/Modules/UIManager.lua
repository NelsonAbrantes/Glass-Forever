local Core, Constants, Utils = unpack(select(2, ...))
local UIManager = Core:GetModule("UIManager")

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
local ChatFrameChannelButton = ChatFrameChannelButton
local ChatFrameMenuButton = ChatFrameMenuButton
local CreateFrame = CreateFrame
local FCFDock_GetSelectedWindow = FCFDock_GetSelectedWindow
local FCF_RestorePositionAndDimensions = FCF_RestorePositionAndDimensions
local GENERAL_CHAT_DOCK = GENERAL_CHAT_DOCK
local GetChatWindowInfo = GetChatWindowInfo
local GetCVar = C_CVar and C_CVar.GetCVar or GetCVar
local NUM_CHAT_WINDOWS = NUM_CHAT_WINDOWS
local QuickJoinToastButton = QuickJoinToastButton
local SetCVar = C_CVar and C_CVar.SetCVar or SetCVar
local UIParent = UIParent
-- luacheck: pop

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

  -- Show the main chat panel on login (after the game has finished loading)
  C_Timer.After(1, function()
    local main = self.state.frames[1]
    if main then
      main:Show()
    end

    -- Windows left undocked last time stay separate normal chat windows
    for i, smf in ipairs(self.state.frames) do
      local chatFrame = smf.chatFrame
      local shown = select(7, GetChatWindowInfo(i))
      if shown and not chatFrame.isDocked and smf.state and not smf.state.isCombatLog then
        smf:ReleaseChatFrame()
        if FCF_RestorePositionAndDimensions then
          FCF_RestorePositionAndDimensions(chatFrame)
        end
        chatFrame:Show()
      end
    end
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
      end
    end)
  end)

  -- Changing the font size from the tab menu resets the font, put Glass' back
  if _G.FCF_SetChatWindowFontSize then
    self:SecureHook("FCF_SetChatWindowFontSize", function (_, chatFrame)
      local smf = FindFrame(chatFrame or _G.FCF_GetCurrentChatFrame and _G.FCF_GetCurrentChatFrame())
      if smf then smf:ApplyGlassFont() end
    end)
  end

  self:SecureHook("FCF_DockFrame", function (chatFrame)
    local smf = FindFrame(chatFrame)
    if smf and smf.state and smf.state.detached then
      smf:TakeOverChatFrame()
    end
  end)

  -- Edit box
  self.editBox = CreateEditBox(self.container)

  -- Fix Battle.net Toast frame position
  BNToastFrame:ClearAllPoints()
  BNToastFrame:SetPoint("BOTTOMLEFT", ChatAlertFrame, "BOTTOMLEFT", 0, 0)

  ChatAlertFrame:ClearAllPoints()
  ChatAlertFrame:SetPoint("BOTTOMLEFT", self.container, "TOPLEFT", 15, 10)

  -- Hide other chat elements
  if Constants.ENV == "retail" then
    QuickJoinToastButton:Hide()
  end

  ChatFrameChannelButton:Hide()
  ChatFrameMenuButton:Hide()

  -- New version alert
  --@non-debug@
  -- Any change counts, not only a higher number: the fork restarted its
  -- numbering at 0.9.x after the first beta was released as 1.9.0-forever1.
  if Core.db.global.version ~= Core.Version then
    Utils.notify('Glass has just been updated. |cFFFFFF00|Hgarrmission:Glass:opennews|h[See what’s new]|h|r')
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
  self:RawHook("FCF_OpenTemporaryWindow", function (...)
    local chatFrame = self.hooks["FCF_OpenTemporaryWindow"](...)
    local smf = self.slidingMessageFramePool:Acquire()
    smf:Init(chatFrame)

    self.state.temporaryFrames[chatFrame:GetName()] = smf
    self.state.temporaryTabs[chatFrame:GetName()] = CreateChatTab(smf)
    return chatFrame
  end, true)

  -- Close window
  self:RawHook("FCF_Close", function (chatFrame, ...)
    self.hooks["FCF_Close"](chatFrame, ...)

    local name = chatFrame and chatFrame:GetName()
    local smf = name and self.state.temporaryFrames[name]
    if smf then
      self.slidingMessageFramePool:Release(smf)
      self.state.temporaryFrames[name] = nil
      self.state.temporaryTabs[name] = nil
    end
  end, true)

  -- Light up a tab when a message of one of its chat types arrives and the tab
  -- is not selected. The glow takes the color of the chat type (guild green,
  -- party blue, etc). Blizzard only flashes tabs for whispers by default, see
  -- the FCF_StartAlertFlash hook below for those.
  -- The color itself is applied in ChatTab.lua through tab.glowColor.
  local ALERT_SECONDS = 10 -- how long the dock stays visible after a message
  local ALERT_EVENTS = {
    CHAT_MSG_SAY = "SAY",
    CHAT_MSG_YELL = "YELL",
    CHAT_MSG_EMOTE = "EMOTE",
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
      self.dock:HideDelay(ALERT_SECONDS)
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
  -- which made messages appear twice. Uses the original Hide so the Glass
  -- panel itself is not hidden.
  local function HideBlizzardFrame(smf)
    local chatFrame = smf.chatFrame
    if smf.state and smf.state.detached then return end -- a separate window, leave it
    if chatFrame and chatFrame:IsShown() then
      local hooks = smf.hooks and smf.hooks[chatFrame]
      if hooks and hooks.Hide then
        hooks.Hide(chatFrame)
      end
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
    -- SELECTED_CHAT_FRAME but shouldn't empty Glass.
    local selected = _G.SELECTED_CHAT_FRAME
    if FCFDock_GetSelectedWindow and GENERAL_CHAT_DOCK then
      selected = FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK) or selected
    end
    if selected then
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

    self.timeElapsed = self.timeElapsed + elapsed

    while (self.timeElapsed > 0.01) do
      self.timeElapsed = self.timeElapsed - 0.01

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
