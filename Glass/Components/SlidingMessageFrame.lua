local Core, Constants, Utils = unpack(select(2, ...))
local TP = Core:GetModule("TextProcessing")

local AceHook = Core.Libs.AceHook

local LibEasing = Core.Libs.LibEasing
local LSM = Core.Libs.LSM
local lodash = Core.Libs.lodash
local reduce = lodash.reduce

local CreateMessageLinePool = Core.Components.CreateMessageLinePool
local CreateScrollOverlayFrame = Core.Components.CreateScrollOverlayFrame

local MOUSE_ENTER = Constants.EVENTS.MOUSE_ENTER
local MOUSE_LEAVE = Constants.EVENTS.MOUSE_LEAVE
local UPDATE_CONFIG = Constants.EVENTS.UPDATE_CONFIG

-- luacheck: push ignore 113
local CreateFrame = CreateFrame
local CreateObjectPool = CreateObjectPool
local DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME
local Mixin = Mixin
-- luacheck: pop

-- Starts a message's fade out, unless "Fade out" is off in the Messages
-- options (then messages stay visible)
local function FadeOutLater(message)
  if Core.db.profile.messageFade ~= false then
    message:HideDelay(Core.db.profile.chatHoldTime)
  end
end

-- Retail 12.x can return "secret" numbers from scroll frame getters, which
-- addons cannot do arithmetic on. Fall back to values we control ourselves.
local function GetScrollRange(frame)
  local range = frame:GetVerticalScrollRange()
  if issecretvalue and issecretvalue(range) then
    local sliderHeight = frame.slider and frame.slider:GetHeight() or 0
    local frameHeight = frame:GetHeight()
    if (issecretvalue(sliderHeight)) or (issecretvalue(frameHeight)) then
      return 0
    end
    range = math.max(sliderHeight - frameHeight, 0)
  end
  return range
end

local function GetScroll(frame)
  local scroll = frame:GetVerticalScroll()
  if issecretvalue and issecretvalue(scroll) then
    return GetScrollRange(frame)
  end
  return scroll
end

----
-- SlidingMessageFrameMixin
--
-- Custom frame for displaying pretty sliding messages
local SlidingMessageFrameMixin = {}

function SlidingMessageFrameMixin:Init(chatFrame)
  self.config = {
    height = Core.db.profile.frameHeight - Utils.TabBarHeight() - 5,
    width = Core.db.profile.frameWidth,
    overflowHeight = 60,
  }
  self.state = {
    mouseOver = false,
    showingTooltip = false,
    prevEasingHandle = nil,
    incomingScrollbackMessages = {},
    incomingMessages = {},
    messages = {},
    head = nil,
    tail = nil,
    isCombatLog = false,
    detached = false,
    scrollAtBottom = true,
    unreadMessages = false,
  }
  self.chatFrame = chatFrame

  -- Override Blizzard UI
  _G[chatFrame:GetName().."ButtonFrame"]:Hide()

  chatFrame:SetClampRectInsets(0,0,0,0)
  chatFrame:SetClampedToScreen(false)
  chatFrame:SetResizable(false)
  chatFrame:SetParent(self:GetParent())
  chatFrame:ClearAllPoints()

  -- Skip combat log
  if chatFrame == _G.ChatFrame2 then
    self.state.isCombatLog = true
    -- Inset the combat log by the same margin the other tabs use,
    -- so the text isn't cut off at the edge of the container.
    -- Secure (after the fact) hook: replacing the game's functions taints its
    -- chat code, which then can't handle "secret" messages
    self:SecureHook(chatFrame, "SetPoint", function ()
      self:PlaceCombatLog()
    end)
    self:PlaceCombatLog()

    -- Follow the tab bar height (Tabs options)
    if self.combatLogSubscription == nil then
      self.combatLogSubscription = Core:Subscribe(UPDATE_CONFIG, function (key)
        if key == "tabBarHeight" or key == "tabBarPosition" then
          self:PlaceCombatLog()
        end
      end)
    end
    return
  end

  -- Chat scroll frame
  self:SetHeight(self.config.height + self.config.overflowHeight)
  self:SetWidth(self.config.width)
  self:UpdateFramePosition()

  -- Set initial scroll position
  self:SetVerticalScroll(self.config.overflowHeight)

  -- Overlay
  if self.overlay == nil then
    self.overlay = CreateScrollOverlayFrame(self)
    self.overlay:QuickHide()

    -- Snap to bottom on click
    self.overlay:SetScript("OnClickSnapFrame", function ()
      self.state.scrollAtBottom = true
      self.state.unreadMessages = false
      self.overlay:Hide()
      self.overlay:HideNewMessageAlert()

      local startOffset = math.max(
        GetScrollRange(self) - self.config.height * 2,
        GetScroll(self)
      )
      local endOffset = GetScrollRange(self)

      LibEasing:Ease(
        function (offset) self:SetVerticalScroll(offset) end,
        startOffset,
        endOffset,
        0.3,
        LibEasing.OutCubic,
        function ()
          self:SetHeight(self.config.height + self.config.overflowHeight)
        end
      )
    end)
  end

  -- Scrolling
  self:SetScript("OnMouseWheel", function (frame, delta)
    local maxScroll = (
      self.state.scrollAtBottom and
      GetScrollRange(self) + self.config.overflowHeight
      or GetScrollRange(self)
    )
    local minScroll = self.config.height + self.config.overflowHeight
    local scrollValue

    if delta < 0 then
      -- Scroll down
      scrollValue = math.min(GetScroll(self) + 20, maxScroll)
    else
      -- Scroll up
      scrollValue = math.max(GetScroll(self) - 20, math.min(minScroll, maxScroll))
    end

    self:UpdateScrollChildRect()
    self:SetVerticalScroll(scrollValue)

    self.state.scrollAtBottom = scrollValue == maxScroll

    -- Adjust height of scroll frame when scrolling
    if self.state.scrollAtBottom then
      -- If scrolled to the bottom, the height of the scroll frame should
      -- include overflow to account for slide up animations
      self:SetHeight(self.config.height + self.config.overflowHeight)
      self.overlay:Hide()
      self.overlay:HideNewMessageAlert()
      self.state.unreadMessages = false
    else
      -- If not, the height should fit the frame exactly so messages don't spill
      -- under the edit box area
      self:SetHeight(self.config.height)
      self.overlay:Show()
    end

    -- Show hidden messages
    for _, message in ipairs(self.state.messages) do
      message:Show()
    end
  end)

  -- When a tab is shown (e.g. clicked while the mouse is over the chat), bring
  -- its messages up to date with the mouse, since hidden tabs skip the mouse
  -- enter/leave handlers below
  self:SetScript("OnShow", function ()
    if self.state.mouseOver and Core.db.profile.chatShowOnMouseOver then
      for _, message in ipairs(self.state.messages) do
        message:Show()
      end
    elseif not self.state.mouseOver then
      -- Messages that arrived while hidden never started fading out
      for _, message in ipairs(self.state.messages) do
        FadeOutLater(message)
      end
    end
  end)

  -- Mouse clickthrough
  self:EnableMouse(false)

  -- ScrollChild
  if self.slider == nil then
    self.slider = CreateFrame("Frame", nil, self)
  end
  self.slider:SetHeight(self.config.height + self.config.overflowHeight)
  self.slider:SetWidth(self.config.width)
  self:SetScrollChild(self.slider)

  if self.slider.bg == nil then
    self.slider.bg = self.slider:CreateTexture(nil, "BACKGROUND")
  end
  self.slider.bg:SetAllPoints()
  self.slider.bg:SetColorTexture(0, 0, 1, 0)

  -- Pool for the message frames
  if self.messageFramePool == nil then
    self.messageFramePool = CreateMessageLinePool(self.slider)
  end

  -- Secure hooks run after the game's code instead of replacing it, so the
  -- game can still handle "secret" messages (replacing taints its chat code)
  self:SecureHook(chatFrame, "AddMessage", function (...)
    self:AddMessage(...)
  end)

  self:SecureHook(chatFrame.historyBuffer, "PushBack", function (_, message)
    -- The game restored old messages itself (History won't add its own)
    self.state.didBackfill = true
    self:BackFillMessage(nil, message.message, message.r, message.g, message.b)
  end)

  -- Hide the default chat frame and show the sliding message frame instead
  self:TakeOverChatFrame()

  -- Load any messages already in the chat frame to Glass
  if chatFrame == DEFAULT_CHAT_FRAME then
    for i = 1, chatFrame:GetNumMessages() do
        local text, r, g, b = chatFrame:GetMessageInfo(i);
        self:AddMessage(chatFrame, text, r, g, b);
      end
  end

  -- Listeners
  if self.subscriptions == nil then
    self.subscriptions = {
      Core:Subscribe(MOUSE_ENTER, function ()
        -- Don't hide chats when mouse is over
        self.state.mouseOver = true

        -- Only the tab being shown: doing this for every tab started up to
        -- 128 animations per tab at once, a frame rate spike each time the
        -- mouse entered the chat. Hidden tabs catch up in OnShow.
        if not self:IsShown() then return end

        if not self.state.scrollAtBottom then
          self.overlay:Show()
        end

        for _, message in ipairs(self.state.messages) do
          if Core.db.profile.chatShowOnMouseOver then
            message:Show()
          end
        end
      end),
      Core:Subscribe(MOUSE_LEAVE, function ()
        -- Hide chats when mouse leaves
        self.state.mouseOver = false

        if not self:IsShown() then return end

        self.overlay:HideDelay(Core.db.profile.chatHoldTime)

        for _, message in ipairs(self.state.messages) do
          FadeOutLater(message)
        end
      end),
      Core:Subscribe(UPDATE_CONFIG, function (key)
        if key == "messageFade" then
          for _, message in ipairs(self.state.messages) do
            if Core.db.profile.messageFade == false then
              message:Show()
            elseif not self.state.mouseOver then
              message:HideDelay(Core.db.profile.chatHoldTime)
            end
          end
        end

        -- Separate windows follow the Glass font too
        if key == "font" then
          self:ApplyGlassFont()
        end

        if self.state.isCombatLog == false then
          if (
            key == "font" or
            key == "messageFontSize" or
            key == "frameWidth" or
            key == "frameHeight" or
            key == "messageLeading" or
            key == "messageLinePadding" or
            key == "indentWordWrap" or
            key == "tabBarHeight" or
            key == "tabBarPosition"
          ) then
            -- Adjust frame dimensions first (messages start below the tab bar)
            self.config.height = Core.db.profile.frameHeight - Utils.TabBarHeight() - 5
            self:UpdateFramePosition()
            self.config.width = Core.db.profile.frameWidth

            self:SetHeight(self.config.height + self.config.overflowHeight)
            self:SetWidth(self.config.width)

            -- Then adjust message line dimensions
            for _, message in ipairs(self.state.messages) do
                message:UpdateFrame()
            end

            -- Then update scroll values
            local contentHeight = reduce(self.state.messages, function (acc, message)
              return acc + message:GetHeight()
            end, 0)
            self.slider:SetHeight(self.config.height + self.config.overflowHeight + contentHeight)
            self.slider:SetWidth(self.config.width)

            self.state.scrollAtBottom = true
            self.state.unreadMessages = false
            self:UpdateScrollChildRect()
            self:SetVerticalScroll(GetScrollRange(self) + self.config.overflowHeight)
            self.overlay:Hide()
            self.overlay:HideNewMessageAlert()
          end

          if key == "chatBackgroundOpacity" then
            for _, message in ipairs(self.state.messages) do
              message:UpdateTextures()
            end
          end
        end
      end)
    }
  end
end

---
-- Puts the default chat frame under Glass' control: hidden, kept in place
-- inside the Glass container, and replaced by this frame on screen.
function SlidingMessageFrameMixin:TakeOverChatFrame()
  local chatFrame = self.chatFrame
  self.state.detached = false

  _G[chatFrame:GetName().."ButtonFrame"]:Hide()
  chatFrame:SetClampRectInsets(0,0,0,0)
  chatFrame:SetClampedToScreen(false)
  chatFrame:SetResizable(false)
  chatFrame:SetParent(self:GetParent())

  -- All hooks here are secure: they run after the game's code and undo what it
  -- did, instead of replacing its functions. Replacing taints the game's chat
  -- code, which then fails on "secret" messages. While the window is separate
  -- (detached), they do nothing.
  if not self:IsHooked(chatFrame, "SetPoint") then
    self:SecureHook(chatFrame, "SetPoint", function ()
      if not self.state.detached then
        self:PlaceChatFrame()
      end
    end)
  end
  self:PlaceChatFrame()

  if not self:IsHooked(chatFrame, "Show") then
    self:SecureHook(chatFrame, "Show", function ()
      if self.state.detached then return end
      self:HideChatFrame()
      self:Show()
    end)
  end

  if not self:IsHooked(chatFrame, "Hide") then
    self:SecureHook(chatFrame, "Hide", function ()
      if self.state.detached or self.hidingChatFrame then return end
      self:Hide()
    end)
  end

  chatFrame:Hide()
end

---
-- The messages area: below the tab bar, or from the top of the chat when the
-- tab bar is at the bottom (its height already leaves room for the bar)
function SlidingMessageFrameMixin:UpdateFramePosition()
  local y = Utils.TabBarAtBottom() and 0 or -(Utils.TabBarHeight() + 5)
  self:SetPoint("TOPLEFT", 0, y)
end

---
-- Places the Combat Log (the game's own window) below the tab bar, leaving
-- room for its filter bar ("My actions" / "What happened to me?")
local COMBAT_LOG_FILTER_HEIGHT = 27 -- room for the filter bar, below the tab bar
local COMBAT_LOG_X = 10              -- left/right margin, lined up with the tabs

function SlidingMessageFrameMixin:PlaceCombatLog()
  if self.positioning then return end
  self.positioning = true
  local chatFrame = self.chatFrame
  pcall(function ()
    chatFrame:ClearAllPoints()
    local top, bottom = Utils.TabBarHeight() + COMBAT_LOG_FILTER_HEIGHT, 0
    if Utils.TabBarAtBottom() then
      top, bottom = COMBAT_LOG_FILTER_HEIGHT, Utils.TabBarHeight() + 5
    end
    chatFrame:SetPoint("TOPLEFT", self:GetParent(), "TOPLEFT", COMBAT_LOG_X, -top)
    chatFrame:SetPoint("BOTTOMRIGHT", self:GetParent(), "BOTTOMRIGHT", -COMBAT_LOG_X, bottom)
  end)
  self.positioning = false
end

---
-- Keeps the (hidden) default chat frame at its place in the Glass container
function SlidingMessageFrameMixin:PlaceChatFrame()
  if self.positioning then return end
  self.positioning = true
  pcall(function ()
    self.chatFrame:ClearAllPoints()
    self.chatFrame:SetPoint("TOPLEFT", self:GetParent(), "TOPLEFT", 0, -45)
  end)
  self.positioning = false
end

---
-- Hides the default chat frame without hiding this frame
function SlidingMessageFrameMixin:HideChatFrame()
  self.hidingChatFrame = true
  pcall(self.chatFrame.Hide, self.chatFrame)
  self.hidingChatFrame = false
end

---
-- Gives the chat frame back to the game, as a normal chat window. Used when
-- its tab is dragged out of the Glass dock. Messages keep arriving here, so
-- they are still there when the tab is docked again (TakeOverChatFrame).
function SlidingMessageFrameMixin:ReleaseChatFrame()
  local chatFrame = self.chatFrame

  -- The hooks stay, but do nothing while detached
  self.state.detached = true

  chatFrame:SetParent(_G.UIParent)
  chatFrame:SetClampedToScreen(true)
  chatFrame:SetResizable(true)
  _G[chatFrame:GetName().."ButtonFrame"]:Show()

  self:Hide()
  self:ApplyGlassFont()
end

---
-- Gives a separate chat window the Glass font and outline. The size stays the
-- window's own, so it can still be changed from the tab menu (Font Size).
function SlidingMessageFrameMixin:ApplyGlassFont()
  if not self.state.detached then return end

  local chatFrame = self.chatFrame
  local _, size = chatFrame:GetFont()
  chatFrame:SetFont(
    LSM:Fetch(LSM.MediaType.FONT, Core.db.profile.font),
    size or Core.db.profile.messageFontSize,
    Core.db.profile.fontFlags
  )
end

function SlidingMessageFrameMixin:CreateMessageFrame(frame, text, red, green, blue, messageId, holdTime)
  red = red or 1
  green = green or 1
  blue = blue or 1

  local message = self.messageFramePool:Acquire()

  -- Original text and color, kept so the History module can save them
  message.raw = { text = text, r = red, g = green, b = blue }

  message.text:SetTextColor(red, green, blue, 1)
  message.text:SetText(TP:ProcessText(text))

  -- Adjust height to contain text
  message:UpdateFrame()

  return message
end

function SlidingMessageFrameMixin:AddMessage(...)
  -- Enqueue messages to be displayed
  local args = {...}
  table.insert(self.state.incomingMessages, args)
end

function SlidingMessageFrameMixin:BackFillMessage(...)
  local args = {...}
  table.insert(self.state.incomingScrollbackMessages, args)
end

function SlidingMessageFrameMixin:OnFrame()
  if #self.state.incomingMessages > 0 then
    local incoming = {}
    for _, message in ipairs(self.state.incomingMessages) do
      table.insert(incoming, message)
    end
    self.state.incomingMessages = {}
    self:Update(incoming, false)
  end

  if #self.state.incomingScrollbackMessages > 0 then
    local incoming = {}
    for _, message in ipairs(self.state.incomingScrollbackMessages) do
      table.insert(incoming, message)
    end
    self.state.incomingScrollbackMessages = {}
    self:Update(incoming, true)
  end
end

function SlidingMessageFrameMixin:Update(incoming, reverse)
  -- Create new message frame for each message
  local newMessages = {}

  for _, message in ipairs(incoming) do
    local messageFrame = self:CreateMessageFrame(unpack(message))
    messageFrame:SetPoint("BOTTOMLEFT")

    -- Attach previous messageFrame to this one
    if reverse then
      if self.state.tail then
        messageFrame:ClearAllPoints()
        messageFrame:SetPoint("BOTTOMLEFT", self.state.tail, "TOPLEFT")
      end
    else
      if self.state.head then
        self.state.head:ClearAllPoints()
        self.state.head:SetPoint("BOTTOMLEFT", messageFrame, "TOPLEFT")
      end
    end

    if self.state.tail == nil then
      self.state.tail = messageFrame
    end

    if self.state.head == nil then
      self.state.head = messageFrame
    end

    if reverse then
      self.state.tail = messageFrame
    else
      self.state.head = messageFrame
    end

    table.insert(newMessages, messageFrame)
  end

  -- Update slider offsets animation
  local offset = reduce(newMessages, function (acc, message)
    return acc + message:GetHeight()
  end, 0)

  local newHeight = self.slider:GetHeight() + offset
  self.slider:SetHeight(newHeight)

  -- Display and run everything
  if self.state.scrollAtBottom then
    -- Only play slide up if not scrolling
    if self.state.prevEasingHandle ~= nil then
      LibEasing:StopEasing(self.state.prevEasingHandle)
    end

    local startOffset = GetScroll(self)
    local endOffset = newHeight - self:GetHeight() + self.config.overflowHeight

    if Core.db.profile.chatSlideInDuration > 0 then
      self.state.prevEasingHandle = LibEasing:Ease(
        function (n) self:SetVerticalScroll(n) end,
        startOffset,
        endOffset,
        Core.db.profile.chatSlideInDuration,
        LibEasing.OutCubic
      )
    else
      self:SetVerticalScroll(endOffset)
    end
  else
    -- Otherwise show "Unread messages" notification
    self.state.unreadMessages = true
    self.overlay:Show()
    self.overlay:ShowNewMessageAlert()
    if not self.state.mouseOver then
      self.overlay:HideDelay(Core.db.profile.chatHoldTime)
    end
  end

  for _, message in ipairs(newMessages) do
    message:Show()
    if not self.state.mouseOver then
      FadeOutLater(message)
    end
    if reverse then
      table.insert(self.state.messages, 1, message)
    else
      table.insert(self.state.messages, message)
    end
  end

  -- Release old messages
  -- Removed in place: building new lists for every message made garbage the
  -- game had to clean up now and then (a frame rate hitch in busy chats)
  local historyLimit = 128
  while #self.state.messages > historyLimit do
    self.messageFramePool:Release(table.remove(self.state.messages, 1))
  end
end

local function CreateSlidingMessageFrame(name, parent, chatFrame)
  local frame = CreateFrame("ScrollFrame", name, parent)
  local object = Mixin(frame, SlidingMessageFrameMixin)
  AceHook:Embed(object)

  if chatFrame then
    object:Init(chatFrame)
  end
  object:Hide()
  return object
end

local function CreateSlidingMessageFramePool(parent)
  return CreateObjectPool(
    function () return CreateSlidingMessageFrame(nil, parent) end,
    function (_, smf)
      smf:Hide()

      if smf.chatFrame then
        smf:Unhook(smf.chatFrame, "SetPoint")
        smf:Unhook(smf.chatFrame, "AddMessage")
        smf:Unhook(smf.chatFrame, "Show")
        smf:Unhook(smf.chatFrame, "Hide")
        -- Remove the historyBuffer hook too, so a reused chat window (e.g. a
        -- whisper tab) can be initialized again without "rehook" errors.
        if smf.chatFrame.historyBuffer then
          smf:Unhook(smf.chatFrame.historyBuffer, "PushBack")
        end
      end

      if smf.state ~= nil then
        smf.state.head = nil
        smf.state.tail = nil
        smf.state.messages = {}
        smf.state.incomingMessages = {}
        smf.state.incomingScrollbackMessages = {}
      end

      if smf.messageFramePool ~= nil then
        smf.messageFramePool:ReleaseAll()
      end
    end
  )
end

Core.Components.CreateSlidingMessageFrame = CreateSlidingMessageFrame
Core.Components.CreateSlidingMessageFramePool = CreateSlidingMessageFramePool
