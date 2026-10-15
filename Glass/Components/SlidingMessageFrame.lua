local Core, Constants, Utils = unpack(select(2, ...))
local TP = Core:GetModule("TextProcessing")
local SpamFilter = Core:GetModule("SpamFilter")

local AceHook = Core.Libs.AceHook

local LibEasing = Core.Libs.LibEasing
local LSM = Core.Libs.LSM

local CreateMessageLinePool = Core.Components.CreateMessageLinePool
local CreateScrollOverlayFrame = Core.Components.CreateScrollOverlayFrame

local Colors = Constants.COLORS

local MOUSE_ENTER = Constants.EVENTS.MOUSE_ENTER
local MOUSE_LEAVE = Constants.EVENTS.MOUSE_LEAVE
local UPDATE_CONFIG = Constants.EVENTS.UPDATE_CONFIG

-- luacheck: push ignore 113
local CreateFont = CreateFont
local CreateFrame = CreateFrame
local GetChatWindowInfo = GetChatWindowInfo
local CreateObjectPool = CreateObjectPool
local DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME
local Mixin = Mixin
local C_Timer = C_Timer
-- luacheck: pop

-- Settings that move or resize the chat without changing the size of the
-- messages in it
local RELAYOUT_KEEPS_MESSAGES = {
  frameHeight = true,
  tabBarHeight = true,
  tabBarPosition = true,
}

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
      self:HideMessagesLater()
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

        if self.leaveTimer then
          self.leaveTimer:Cancel()
          self.leaveTimer = nil
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

        self:HideMessagesLater()
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
        if key == "font" or key == "messageLeading" then
          self:ApplyGlassFont()
        end

        -- ...and the Glass look, with its fade and background settings
        if self.state.detached and (key == "windowStyle" or key == "chatHoldTime"
          or key == "chatFadeOutDuration" or key == "chatBackgroundOpacity") then
          self:ApplyWindowStyle()
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

            -- Then adjust message line dimensions. Only what changes the size
            -- of the messages themselves: the chat's height and the tab bar
            -- don't, and measuring every saved message of every tab again at
            -- each step of the Height slider froze the game.
            if not RELAYOUT_KEEPS_MESSAGES[key] then
              for _, message in ipairs(self.state.messages) do
                message:UpdateFrame()
              end
            end

            -- Then update scroll values
            local contentHeight = 0
            for _, message in ipairs(self.state.messages) do
              contentHeight = contentHeight + message:GetHeight()
            end
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

  self:Hide()
  self:ApplyGlassFont()
  self:ApplyWindowStyle()
end

-- The background of a separate window: how much of the width fades in at each
-- side, and how far it reaches past the window's edges (room around the text)
local WINDOW_FADE_RATIO = 0.3
local WINDOW_BG_PAD_X = 10
local WINDOW_BG_PAD_Y = 4
-- How much of the chat background opacity the window uses: all of it, so it
-- looks like the main chat (less looked lighter)
local WINDOW_BG_STRENGTH = 1

local function WindowFade(chatFrame)
  return math.max(40, math.floor(chatFrame:GetWidth() * WINDOW_FADE_RATIO))
end

-- The window's border pieces (FloatingBorderedFrame)
local WINDOW_BORDER = {
  "TopLeftTexture", "TopRightTexture", "BottomLeftTexture", "BottomRightTexture",
  "LeftTexture", "RightTexture", "TopTexture", "BottomTexture",
}

---
-- True while this window is separate and uses the Glass look (Options >
-- General > Separate windows)
function SlidingMessageFrameMixin:UsesWindowStyle()
  return self.state.detached and Core.db.profile.windowStyle ~= false
end

---
-- Gives a separate window the Glass look: no border or side buttons, the
-- Glass fading background (shown while the mouse is over the window, like the
-- game's own), and messages that fade out like in Glass. The window stays the
-- game's own, so it can still be moved, resized and docked again. With the
-- option off it looks like the default chat.
function SlidingMessageFrameMixin:ApplyWindowStyle()
  local chatFrame = self.chatFrame
  local name = chatFrame:GetName()
  local glass = self:UsesWindowStyle()

  _G[name.."ButtonFrame"]:Show()

  -- Keep the border of the window and of its side buttons hidden: the game
  -- shows them again on mouse over
  local parts = {}
  for _, part in ipairs(WINDOW_BORDER) do
    table.insert(parts, name..part)
    table.insert(parts, name.."ButtonFrame"..part)
  end
  table.insert(parts, name.."ButtonFrameBackground")
  for _, part in ipairs(parts) do
    local texture = _G[part]
    if texture then
      if not self:IsHooked(texture, "SetAlpha") then
        self:SecureHook(texture, "SetAlpha", function (_, alpha)
          if self:UsesWindowStyle() and alpha ~= 0 then texture:SetAlpha(0) end
        end)
      end
      texture:SetAlpha(glass and 0 or 1)
    end
  end

  -- The minimize and resize buttons in the style of the chat buttons
  local chatButtons = Core:GetModule("UIManager").chatButtons
  local minimize = _G[name.."ButtonFrameMinimizeButton"]
  local resize = chatFrame.ResizeButton or _G[name.."ResizeButton"]
  if chatButtons then
    if minimize then
      if glass then chatButtons:Restyle(minimize, "buttonMinimize") else chatButtons:Unstyle(minimize) end
    end
    if resize then
      if glass then chatButtons:Restyle(resize, "buttonResize", 16, 14) else chatButtons:Unstyle(resize) end
    end
  end
  self:StyleScrollBar(glass, chatButtons)

  -- The Glass background follows the game's: it fades in and out with the
  -- mouse, the game's own stays invisible
  local background = _G[name.."Background"]
  if background then
    if chatFrame.leftBg == nil then
      local fade = WindowFade(chatFrame)
      Core.Components.GradientBackgroundMixin.SetGradientBackground(chatFrame, fade, fade, Colors.codGray, 0)
      for _, texture in ipairs({ chatFrame.leftBg, chatFrame.centerBg, chatFrame.rightBg }) do
        texture:SetDrawLayer("BACKGROUND", -8)
      end
      -- A bit past the window's edges, so the text isn't right at the border
      chatFrame.leftBg:ClearAllPoints()
      chatFrame.leftBg:SetPoint("TOPLEFT", chatFrame, "TOPLEFT", -WINDOW_BG_PAD_X, WINDOW_BG_PAD_Y)
      chatFrame.leftBg:SetPoint("BOTTOMLEFT", chatFrame, "BOTTOMLEFT", -WINDOW_BG_PAD_X, -WINDOW_BG_PAD_Y)
      chatFrame.rightBg:ClearAllPoints()
      chatFrame.rightBg:SetPoint("TOPRIGHT", chatFrame, "TOPRIGHT", WINDOW_BG_PAD_X, WINDOW_BG_PAD_Y)
      chatFrame.rightBg:SetPoint("BOTTOMRIGHT", chatFrame, "BOTTOMRIGHT", WINDOW_BG_PAD_X, -WINDOW_BG_PAD_Y)

      -- The fade follows the width when the window is resized
      chatFrame:HookScript("OnSizeChanged", function ()
        if self:UsesWindowStyle() then
          self:ShowWindowBackground(self.windowBackgroundAlpha)
        end
      end)
    end

    if not self:IsHooked(background, "SetAlpha") then
      self:SecureHook(background, "SetAlpha", function (_, alpha)
        if not self:UsesWindowStyle() or self.settingBackground then return end
        self:ShowWindowBackground(alpha)
      end)
    end

    self:ShowWindowBackground(glass and background:GetAlpha() or nil)
  end

  -- Messages fade out like in Glass (the game's own fading, with Glass' timing)
  if glass then
    chatFrame:SetFading(true)
    chatFrame:SetTimeVisible(Core.db.profile.chatHoldTime)
    chatFrame:SetFadeDuration(Core.db.profile.chatFadeOutDuration)
  end

  self:StyleMinimizedFrame()
end

local SCROLL_LINE_ALPHA = 0.15 -- the thin line along the scroll bar
local SCROLL_THUMB_WIDTH = 3
local SCROLL_SETTLE = 0.08 -- seconds the marker must stay put before the Glass one follows

-- Keeps a piece of the game's scroll bar art invisible with the Glass look
-- (the game shows it again on mouse over), or gives it back
local function ScrollArt(smf, region, glass)
  if region.glassOwnArt then return end
  if not smf:IsHooked(region, "SetAlpha") then
    smf:SecureHook(region, "SetAlpha", function (_, alpha)
      if smf:UsesWindowStyle() and alpha ~= 0 then region:SetAlpha(0) end
    end)
  end
  region:SetAlpha(glass and 0 or 1)
end

---
-- The scroll bar of a separate window in the Glass look: a thin faint line
-- with a slim marker in the Glass color (white under the mouse), and arrows
-- like the chat buttons
function SlidingMessageFrameMixin:StyleScrollBar(glass, chatButtons)
  local chatFrame = self.chatFrame
  local scrollBar = chatFrame.ScrollBar
  local track = scrollBar and scrollBar.Track
  local thumb = track and track.Thumb

  if track then
    for _, region in ipairs({ track:GetRegions() }) do ScrollArt(self, region, glass) end
    if not track.glassLine then
      local line = track:CreateTexture(nil, "ARTWORK")
      line.glassOwnArt = true
      line:SetColorTexture(1, 1, 1, SCROLL_LINE_ALPHA)
      line:SetWidth(1)
      line:SetPoint("TOP", 0, -2)
      line:SetPoint("BOTTOM", 0, 2)
      track.glassLine = line
    end
    track.glassLine:SetShown(glass)
  end

  if thumb then
    for _, region in ipairs({ thumb:GetRegions() }) do ScrollArt(self, region, glass) end
    if not thumb.glassBar then
      -- On the line, following the game's marker: a new message moves that
      -- one for a moment (the window grows before it scrolls down), which
      -- made this one flicker. A move that doesn't last isn't followed;
      -- dragging is followed at once.
      local bar = (track or thumb):CreateTexture(nil, "OVERLAY")
      bar.glassOwnArt = true
      bar:SetColorTexture(1, 1, 1, 1)
      bar:SetWidth(SCROLL_THUMB_WIDTH)
      bar:SetPoint("TOP", thumb, "TOP", 0, -1)
      bar:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 1)
      thumb.glassBar = bar
      if track then
        track:HookScript("OnUpdate", function ()
          if not bar:IsShown() then return end
          local trackTop, top, bottom = track:GetTop(), thumb:GetTop(), thumb:GetBottom()
          if not (trackTop and top and bottom) then return end
          top, bottom = top - trackTop, bottom - trackTop
          local now = GetTime()
          if top ~= bar.wantTop or bottom ~= bar.wantBottom then
            bar.wantTop, bar.wantBottom, bar.wantSince = top, bottom, now
          end
          if (top ~= bar.shownTop or bottom ~= bar.shownBottom)
            and (thumb:IsMouseOver() or now - bar.wantSince >= SCROLL_SETTLE) then
            bar.shownTop, bar.shownBottom = top, bottom
            bar:ClearAllPoints()
            bar:SetPoint("TOP", track, "TOP", 0, top - 1)
            bar:SetPoint("BOTTOM", track, "TOP", 0, bottom + 1)
          end
        end)
      end
      local function Color(hover)
        if hover then
          bar:SetVertexColor(1, 1, 1, 1)
        else
          bar:SetVertexColor(Colors.apache.r, Colors.apache.g, Colors.apache.b, 0.8)
        end
      end
      Color(false)
      thumb:HookScript("OnEnter", function () Color(true) end)
      thumb:HookScript("OnLeave", function () Color(false) end)
    end
    thumb.glassBar:SetShown(glass)
  end

  if chatButtons then
    local buttons = {
      { scrollBar and scrollBar.Back, "buttonScrollUp", 16, 12 },
      { scrollBar and scrollBar.Forward, "buttonScrollDown", 16, 12 },
      { chatFrame.ScrollToBottomButton, "buttonScrollBottom", 16, 14 },
    }
    for _, entry in ipairs(buttons) do
      local button = entry[1]
      if button then
        if glass then chatButtons:Restyle(button, entry[2], entry[3], entry[4]) else chatButtons:Unstyle(button) end
      end
    end
  end
end

local MINIMIZED_ART = { "Left", "Right", "Middle", "HighlightLeft", "HighlightRight", "HighlightMiddle" }

---
-- A minimized separate window (the bar with its name) in the Glass look: the
-- fading background, the name in the tab font and color, and a maximize
-- button like the chat buttons. The game creates it the first time the window
-- is minimized.
function SlidingMessageFrameMixin:StyleMinimizedFrame()
  local minFrame = self.chatFrame.minFrame
  if not minFrame then return end
  local glass = self:UsesWindowStyle()

  for _, key in ipairs(MINIMIZED_ART) do
    local texture = minFrame[key]
    if texture then
      if not self:IsHooked(texture, "SetAlpha") then
        self:SecureHook(texture, "SetAlpha", function (_, alpha)
          if self:UsesWindowStyle() and alpha ~= 0 then texture:SetAlpha(0) end
        end)
      end
      texture:SetAlpha(glass and 0 or 1)
    end
  end

  local GradientBackgroundMixin = Core.Components.GradientBackgroundMixin
  local opacity = glass and math.max(Core.db.profile.chatBackgroundOpacity * 0.8, 0.35) or 0
  GradientBackgroundMixin.SetGradientBackground(minFrame, 20, 60, Colors.codGray, opacity)

  -- The name: tab font in the Glass color (a copy, so its color stays)
  if minFrame.glassFont == nil then
    minFrame.glassGameFont = minFrame:GetNormalFontObject()
    minFrame.glassFont = CreateFont(minFrame:GetName().."GlassFont")
  end
  if glass then
    minFrame.glassFont:CopyFontObject(_G.GlassChatDockFont)
    minFrame.glassFont:SetTextColor(Colors.apache.r, Colors.apache.g, Colors.apache.b)
    minFrame.glassFont:SetJustifyH("CENTER")
    minFrame:SetNormalFontObject(minFrame.glassFont)
  elseif minFrame.glassGameFont then
    minFrame:SetNormalFontObject(minFrame.glassGameFont)
  end

  local maximize = _G[minFrame:GetName().."MaximizeButton"]
  local chatButtons = Core:GetModule("UIManager").chatButtons
  if maximize and chatButtons then
    if glass then
      chatButtons:Restyle(maximize, "buttonMaximize")
    else
      chatButtons:Unstyle(maximize)
    end
  end
end

---
-- Shows the Glass background of a separate window at the strength the game
-- gives its own (alpha), and keeps the game's invisible. nil: Glass off.
function SlidingMessageFrameMixin:ShowWindowBackground(alpha)
  local chatFrame = self.chatFrame
  local background = _G[chatFrame:GetName().."Background"]
  local fade = WindowFade(chatFrame)
  local strength = 0
  self.windowBackgroundAlpha = alpha
  if alpha then
    -- The game's background goes up to the window's own opacity setting
    local maxAlpha = select(6, GetChatWindowInfo(chatFrame:GetID())) or 0.25
    strength = math.min(1, alpha / math.max(maxAlpha, 0.01))
  end

  if alpha then
    self.settingBackground = true
    background:SetAlpha(0)
    self.settingBackground = false
  end

  -- Drawn again with the right opacity: a texture's own opacity doesn't mix
  -- well with a fade drawn on it
  local opacity = Core.db.profile.chatBackgroundOpacity * WINDOW_BG_STRENGTH * strength
  Core.Components.GradientBackgroundMixin.SetGradientBackground(chatFrame, fade, fade, Colors.codGray, opacity)
end

---
-- Gives a separate chat window the Glass font and outline. The size stays the
-- window's own, so it can still be changed from the tab menu (Font Size).
function SlidingMessageFrameMixin:ApplyGlassFont()
  if not self.state.detached then return end

  local chatFrame = self.chatFrame
  local _, size = chatFrame:GetFont()
  -- A font of its own (with the game's fonts for Chinese, Korean and Russian
  -- letters, like the main chat), named after the window
  local font = Core:GetModule("Fonts"):Set(
    "GlassWindowFont"..chatFrame:GetID(),
    LSM:Fetch(LSM.MediaType.FONT, Core.db.profile.font),
    size or Core.db.profile.messageFontSize,
    Core.db.profile.fontFlags
  )
  -- The look of the chat messages (shadow, line spacing, left aligned: a
  -- window opened by "Move to New Window" was centered)
  Core:GetModule("Fonts"):StyleLikeMessages(font)
  chatFrame:SetFontObject(font)
end

---
-- All the messages fade out after the hold time (the mouse left the chat, or
-- the tab was shown). One timer for them all instead of one per message (up
-- to 128 each time); showing them on mouse over cancels it.
function SlidingMessageFrameMixin:HideMessagesLater()
  if Core.db.profile.messageFade == false then return end
  if self.leaveTimer then self.leaveTimer:Cancel() end
  if not self.hideMessagesCallback then
    self.hideMessagesCallback = function ()
      self.leaveTimer = nil
      if self.state.mouseOver then return end
      for _, message in ipairs(self.state.messages) do
        if message:IsShown() then message:Hide() end
      end
    end
  end
  self.leaveTimer = C_Timer.NewTimer(Core.db.profile.chatHoldTime, self.hideMessagesCallback)
end

function SlidingMessageFrameMixin:CreateMessageFrame(frame, text, red, green, blue, messageId, holdTime)
  red = red or 1
  green = green or 1
  blue = blue or 1

  local message = self.messageFramePool:Acquire()

  -- Original text and color, kept so the History module can save them
  message.raw = { text = text, r = red, g = green, b = blue }
  -- The game's chat window it came from: clicking a link in it tells the
  -- game where (e.g. "Move to New Window" copies that window's settings)
  message.chatFrame = self.chatFrame

  message.text:SetTextColor(red, green, blue, 1)
  -- The "Previous session" separator has a look of its own (MessageLine.lua)
  local separator = Core.Components.SeparatorText(text)
  message.text:SetText(separator or TP:ProcessText(text))
  message:SetSeparator(separator ~= nil)

  -- Adjust height to contain text
  message:UpdateFrame()

  return message
end

function SlidingMessageFrameMixin:AddMessage(...)
  -- Enqueue messages to be displayed. The second argument is the text.
  local args = {...}
  if SpamFilter:IsSpam(args[2]) then return end
  table.insert(self.state.incomingMessages, args)
end

function SlidingMessageFrameMixin:BackFillMessage(...)
  local args = {...}
  if SpamFilter:IsSpam(args[2]) then return end
  table.insert(self.state.incomingScrollbackMessages, args)
end

-- The queued messages are handed over as they are, and the emptied list is
-- kept for the next ones: copying them into new lists every time was garbage
-- the game had to clean up
local function TakeQueue(state, key)
  local queue = state[key]
  local spareKey = key.."Spare"
  state[key] = state[spareKey] or {}
  state[spareKey] = queue
  return queue
end

function SlidingMessageFrameMixin:OnFrame()
  if #self.state.incomingMessages > 0 then
    local incoming = TakeQueue(self.state, "incomingMessages")
    self:Update(incoming, false)
    wipe(incoming)
  end

  if #self.state.incomingScrollbackMessages > 0 then
    local incoming = TakeQueue(self.state, "incomingScrollbackMessages")
    self:Update(incoming, true)
    wipe(incoming)
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
  local offset = 0
  for _, message in ipairs(newMessages) do
    offset = offset + message:GetHeight()
  end

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
