local Core, Constants = unpack(select(2, ...))
local Hyperlinks = Core:GetModule("Hyperlinks")

local OpenCopy = Constants.ACTIONS.OpenCopy
local OpenNews = Constants.ACTIONS.OpenNews

local HYPERLINK_CLICK = Constants.EVENTS.HYPERLINK_CLICK
local HYPERLINK_ENTER = Constants.EVENTS.HYPERLINK_ENTER
local HYPERLINK_LEAVE = Constants.EVENTS.HYPERLINK_LEAVE

-- luacheck: push ignore 113
local BattlePetToolTip_ShowLink = BattlePetToolTip_ShowLink
local BattlePetTooltip = BattlePetTooltip
local GameTooltip = GameTooltip
local ShowUIPanel = ShowUIPanel
local UIParent = UIParent
local strmatch = strmatch
local strsplit = strsplit
-- luacheck: pop

local linkTypes = {
  item = true,
  enchant = true,
  spell = true,
  quest = true,
  achievement = true,
  currency = true,
  battlepet = true,
}

---
-- Right click on a recipe someone linked from their profession window (e.g.
-- "[Alchemy: Greater Healing Potion]"): a menu to track it in the objective
-- tracker (its reagents show there), or stop tracking it. Returns false when
-- the game has no recipe tracking, so the click goes on as usual.
local function RecipeMenu(recipeID, text)
  local TradeSkill, MenuUtil = _G.C_TradeSkillUI, _G.MenuUtil
  if not (TradeSkill and TradeSkill.SetRecipeTracked and TradeSkill.IsRecipeTracked
    and MenuUtil and MenuUtil.CreateContextMenu) then
    return false
  end
  local name = type(text) == "string" and strmatch(text, "%[(.-)%]") or nil
  MenuUtil.CreateContextMenu(nil, function (_, rootDescription)
    if name then rootDescription:CreateTitle(name) end
    local tracked = TradeSkill.IsRecipeTracked(recipeID, false)
    rootDescription:CreateButton(tracked and "Untrack Recipe" or "Track Recipe", function ()
      TradeSkill.SetRecipeTracked(recipeID, not tracked, false)
    end)
  end)
  return true
end

function Hyperlinks:OnInitialize()
  self.state = {
    showingTooltip = nil
  }
end

function Hyperlinks:OnEnable()
  -- Custom hyperlink for [See what's new]
  _G.hooksecurefunc("SetItemRef", function(link)
    local linkType, addon, param1 = strsplit(":", link)
    if linkType == "garrmission" and addon == "Glass" then
      if param1 == "opennews" then
        Core:Dispatch(OpenNews())
      end
    end
  end)

  Core:Subscribe(HYPERLINK_CLICK, function (payload)
    local link, text, button, chatFrame = unpack(payload)

    -- Web links made by Glass: open the copy window, the game can't open them
    local url = strmatch(link, "^glassurl:(.+)$")
    if url then
      Core:Dispatch(OpenCopy({ title = "Glass Forever: Copy link", text = url, height = 140 }))
      return
    end

    -- A linked recipe, right clicked: track it (see RecipeMenu)
    if button == "RightButton" then
      local recipeID = tonumber(strmatch(link, "^enchant:(%d+)"))
      if recipeID and RecipeMenu(recipeID, text) then return end
    end

    -- Use global reference in case some addon has hooked into it for custom
    -- hyperlinks (e.g. Mythic Dungeon Tools, Prat)
    -- The game's chat window the link is in goes along (e.g. a whisper opens
    -- in its box), except for right clicks: the game would attach the menu to
    -- that window, which is hidden under Glass, and the menu didn't show.
    -- (marked while it runs: some menus opened from here are changed, below)
    self.fromGlass, self.clickLink, self.clickChatFrame = true, link, chatFrame
    local frameForGame = button ~= "RightButton" and chatFrame or nil
    local ok, problem = pcall(_G.SetItemRef, link, text, button, frameForGame)
    self.fromGlass = false
    if not ok then geterrorhandler()(problem) end
  end)

  -- "Copy Character Name" in a player's menu opened from the Glass chat: the
  -- game only lets its own menus put text on the clipboard, and blocked it
  -- with an error. Here it opens the Glass copy window instead, with the name
  -- selected (Ctrl+C). The game's own menus (e.g. on your target) are left
  -- as they are.
  local Menu, MenuUtil = _G.Menu, _G.MenuUtil
  local copyText = _G.COPY_CHARACTER_NAME
  if Menu and Menu.ModifyMenu and MenuUtil and MenuUtil.GetElementText and copyText then
    local function ChangeCopy(_, rootDescription, contextData)
      if not self.fromGlass or not rootDescription.EnumerateElementDescriptions then return end
      local name = contextData and contextData.name
      if type(name) ~= "string" then return end
      for _, description in rootDescription:EnumerateElementDescriptions() do
        if MenuUtil.GetElementText(description) == copyText and description.SetResponder then
          description:SetResponder(function ()
            Core:Dispatch(OpenCopy({ title = "Glass Forever: Copy name", text = name, height = 140 }))
          end)
        end
      end
    end
    for _, which in ipairs({ "FRIEND", "FRIEND_OFFLINE", "BN_FRIEND", "BN_FRIEND_OFFLINE", "CHAT_ROSTER",
      "PLAYER", "PARTY", "RAID_PLAYER", "GUILD", "GUILD_OFFLINE",
      "COMMUNITIES_WOW_MEMBER", "COMMUNITIES_GUILD_MEMBER" }) do
      Menu.ModifyMenu("MENU_UNIT_"..which, ChangeCopy)
    end
  end

  -- "Open in Separate Window": moves the channel to a new window, like "Move
  -- to New Window", and takes that window out of the dock, beside the chat
  -- (above it if there's no room on the right). Glass gives it its look.
  local OPEN_SEPARATE = "Open in Separate Window"
  local MOVE_TO_TAB = "Move to New Tab"
  local SEPARATE_WIDTH, SEPARATE_HEIGHT, SEPARATE_GAP = 380, 170, 30
  local function OpenSeparate(chatFrame, chatType, chatTarget)
    local dock = _G.GENERAL_CHAT_DOCK
    local before = {}
    for _, frame in ipairs(dock and dock.DOCKED_CHAT_FRAMES or {}) do before[frame] = true end
    _G.ChatFrameUtil.PopOutChat(chatFrame, chatType, chatTarget)

    local window
    for _, frame in ipairs(dock and dock.DOCKED_CHAT_FRAMES or {}) do
      if not before[frame] then window = frame end
    end
    if not window or not _G.FCF_UnDockFrame then return end

    _G.FCF_UnDockFrame(window)
    window:SetSize(SEPARATE_WIDTH, SEPARATE_HEIGHT)
    -- The size of the chat messages (a new window has the game's own); saved
    -- by the game, so it can still be changed from the tab menu
    if _G.FCF_SetChatWindowFontSize then
      _G.FCF_SetChatWindowFontSize(nil, window, Core.db.profile.messageFontSize)
    end

    -- Where the options say (Options > General > Separate windows), on the
    -- screen: a side without room falls back to above the chat
    local screenWidth, screenHeight = _G.UIParent:GetWidth(), _G.UIParent:GetHeight()
    local x, y = (screenWidth - SEPARATE_WIDTH) / 2, (screenHeight - SEPARATE_HEIGHT) / 2
    local glass = _G.GlassFrame
    local where = Core.db.profile.windowOpenPosition or "above"
    if where ~= "center" and glass and glass:GetRight() then
      local aboveX, aboveY = glass:GetLeft(), glass:GetTop() + SEPARATE_GAP
      if where == "right" then
        x, y = glass:GetRight() + SEPARATE_GAP, glass:GetBottom()
        if x + SEPARATE_WIDTH > screenWidth then x, y = aboveX, aboveY end
      elseif where == "left" then
        x, y = glass:GetLeft() - SEPARATE_GAP - SEPARATE_WIDTH, glass:GetBottom()
        if x < 0 then x, y = aboveX, aboveY end
      else
        x, y = aboveX, aboveY
      end
      -- Kept on the screen, with room on the left for the column of buttons
      -- beside the window (minimize...)
      local buttons = _G[window:GetName().."ButtonFrame"]
      local leftRoom = (buttons and buttons:GetWidth() or 30) + 4
      x = math.max(leftRoom, math.min(x, screenWidth - SEPARATE_WIDTH))
      y = math.max(0, math.min(y, screenHeight - SEPARATE_HEIGHT - 30))
    end
    window:ClearAllPoints()
    window:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", x, y)
    -- Unlocked, so it can be moved straight away
    if _G.FCF_SetLocked then _G.FCF_SetLocked(window, false) end
    -- Its tab above it, as when a tab is dragged out of the dock
    if _G.FCF_SetTabPosition then _G.FCF_SetTabPosition(window, 0) end
    if _G.FCF_UpdateButtonSide then _G.FCF_UpdateButtonSide(window) end
    if _G.FCF_SavePositionAndDimensions then _G.FCF_SavePositionAndDimensions(window) end
  end

  -- "Move to New Window" in a channel's menu opened from the Glass chat: the
  -- game needs the chat window the channel was in (it copies its settings
  -- and moves the channel out of it), which the menu doesn't have here (see
  -- above). It's given that window.
  local moveText = _G.MOVE_TO_NEW_WINDOW
  local ChatFrameUtil = _G.ChatFrameUtil
  if Menu and Menu.ModifyMenu and MenuUtil and MenuUtil.GetElementText and moveText
    and ChatFrameUtil and ChatFrameUtil.PopOutChat then
    Menu.ModifyMenu("MENU_CHAT_FRAME_CHANNEL", function (_, rootDescription)
      local chatFrame, link = self.clickChatFrame, self.clickLink
      if not self.fromGlass or not chatFrame or type(link) ~= "string"
        or not rootDescription.EnumerateElementDescriptions then
        return
      end
      -- "channel:CHANNEL:2", "channel:GUILD"...
      local _, chatType, chatTarget = strsplit(":", link)
      if not chatType then return end
      chatType = strupper(chatType) -- the link has "channel", the game wants "CHANNEL"
      for _, description in rootDescription:EnumerateElementDescriptions() do
        if MenuUtil.GetElementText(description) == moveText and description.SetResponder then
          description:SetResponder(function ()
            ChatFrameUtil.PopOutChat(chatFrame, chatType, chatTarget)
          end)
          -- It opens a new tab in the chat (the separate window is the next
          -- option): named so
          if description.AddInitializer then
            description:AddInitializer(function (button)
              if button.fontString and button.fontString.SetTextToFit then
                button.fontString:SetTextToFit(MOVE_TO_TAB)
              end
            end)
          end
        end
      end

      -- The same, straight into a separate window beside the chat
      if rootDescription.CreateButton then
        local button = rootDescription:CreateButton(OPEN_SEPARATE, function ()
          OpenSeparate(chatFrame, chatType, chatTarget)
        end)
        if _G.FCF_CanOpenNewWindow and not _G.FCF_CanOpenNewWindow() and button.SetEnabled then
          button:SetEnabled(false)
        end
      end
    end)
  end

  Core:Subscribe(HYPERLINK_ENTER, function (payload)
    local link, text = unpack(payload)
    local t = string.match(link, "^(.-):")

    if linkTypes[t] then
      if t == "battlepet" then
        self.state.showingTooltip = BattlePetTooltip
        GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
        BattlePetToolTip_ShowLink(text)
      else
        self.state.showingTooltip = GameTooltip
        ShowUIPanel(GameTooltip)
        GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
      end
    end
  end)

  Core:Subscribe(HYPERLINK_LEAVE, function (link)
    if self.state.showingTooltip then
      self.state.showingTooltip:Hide()
      self.state.showingTooltip = false
    end
  end)
end
